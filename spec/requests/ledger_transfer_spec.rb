require "rails_helper"

RSpec.describe "Ledger Transfer", type: :request do
  # `auth_headers` 既定 sub と揃え、サーバ側の current_user 解決で from_user を引き当てる。
  let!(:default_sub) { "01HYZ0000000000000000000AA" }
  let!(:system_account) { create(:account, :system_issuance) }
  let!(:from_user) { create(:user, external_user_id: default_sub) }
  let!(:to_user) { create(:user, external_user_id: "01HYZ0000000000000000000BB") }
  let!(:idempotency_key) { "transfer-key-12345" }
  let!(:headers) { { "Idempotency-Key" => idempotency_key } }

  before do
    from_user.account.update!(balance_fuju: 500)
    stub_active_introspection
  end

  def post_transfer(params:, headers: self.headers)
    post("/ledger/transfer", params: { ledger: params }, headers: headers)
  end

  describe "POST /ledger/transfer" do
    context "正常系" do
      it "200 で記帳され、from -N / to +N / system_issuance 変化なし" do
        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 100 })
        end.to change { LedgerTransaction.count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(from_user.account.reload.balance_fuju).to eq(400)
        expect(to_user.account.reload.balance_fuju).to eq(100)
        expect(system_account.reload.balance_fuju).to eq(0)
      end

      it "レスポンスボディに tx の主要フィールドと送金後の new_balance が含まれる" do
        post_transfer(params: { to_user_id: to_user.external_user_id, amount: 50, memo: "thanks" })

        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[transaction_id kind artifact_id idempotency_key memo metadata occurred_at created_at new_balance])
        expect(parsed).to include(
          "kind" => "transfer",
          "artifact_id" => nil,
          "idempotency_key" => idempotency_key,
          "memo" => "thanks",
          "new_balance" => 450,
        )
        expect(parsed["occurred_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      it "metadata にネスト Hash を渡すと JSONB にそのまま保存される" do
        metadata = { "gift" => { "reason" => "birthday" } }
        post(
          "/ledger/transfer",
          params: { ledger: { to_user_id: to_user.external_user_id, amount: 10, metadata: metadata } }.to_json,
          headers: headers.merge("Content-Type" => "application/json"),
        )

        expect(response).to have_http_status(:ok)
        tx = LedgerTransaction.last
        expect(tx.metadata).to eq(metadata)
        expect(response.parsed_body["metadata"]).to eq(metadata)
      end

      it "occurred_at を渡さない場合 Time.current が保存される" do
        travel_to Time.zone.local(2026, 4, 18, 10, 0, 0) do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 10 })

          expect(response).to have_http_status(:ok)
          expect(LedgerTransaction.last.occurred_at).to eq(Time.current)
        end
      end

      it "memo 未指定の場合は nil で保存される" do
        post_transfer(params: { to_user_id: to_user.external_user_id, amount: 10 })

        expect(response).to have_http_status(:ok)
        expect(LedgerTransaction.last.memo).to be_nil
      end

      it "残高と等しい amount を送金すると new_balance=0 が返る（境界値）" do
        post_transfer(params: { to_user_id: to_user.external_user_id, amount: 500 })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["new_balance"]).to eq(0)
        expect(from_user.account.reload.balance_fuju).to eq(0)
      end
    end

    # cross-service identity (ULID) に統一した結果、bank 未登録の ULID を to_user_id に
    # 渡したケースを mint と同じく lazy provision でカバーする。
    context "受取人 ID 解決（ULID + lazy provision）" do
      let!(:fresh_external_id) { "01HZZ0000000000000000NEW02" }

      it "bank に未登録の ULID を to_user_id に渡すと新規 User + Account が作られて送金成立" do
        expect(User.find_by(external_user_id: fresh_external_id)).to be_nil

        expect do
          post_transfer(params: { to_user_id: fresh_external_id, amount: 70 })
        end.to(change { User.count }.by(1).and(change { LedgerTransaction.count }.by(1)))

        expect(response).to have_http_status(:ok)
        new_user = User.find_by!(external_user_id: fresh_external_id)
        expect(new_user.account.reload.balance_fuju).to eq(70)
        expect(from_user.account.reload.balance_fuju).to eq(430)
      end
    end

    # 送信元 (current_user) が bank に未登録だった場合、UserProvisioner で lazy 作成され、
    # 残高 0 のため INSUFFICIENT_BALANCE で弾かれる経路を担保する。
    context "送信元 ID 解決（current_user の lazy provision）" do
      let!(:fresh_sub) { "01HZZ0000000000000000NEW03" }

      before { stub_active_introspection(sub: fresh_sub) }

      it "未登録 caller が送金しようとすると from_user が lazy 作成されたうえで残高不足になる" do
        expect(User.find_by(external_user_id: fresh_sub)).to be_nil

        expect do
          post(
            "/ledger/transfer",
            params: { ledger: { to_user_id: to_user.external_user_id, amount: 100 } },
            headers: headers.merge(auth_headers(sub: fresh_sub)),
          )
        end.to change { User.count }.by(1)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig("error", "code")).to eq("INSUFFICIENT_BALANCE")
        new_from = User.find_by!(external_user_id: fresh_sub)
        expect(new_from.account.balance_fuju).to eq(0)
      end
    end

    context "冪等性" do
      it "同一 Idempotency-Key で 2 回 POST しても 1 件だけ作成され、2 回目も 200 で既存を返す" do
        post_transfer(params: { to_user_id: to_user.external_user_id, amount: 100 })
        first_id = response.parsed_body["transaction_id"]

        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 100 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["transaction_id"]).to eq(first_id)
        # 再送経路でも new_balance は「現時点の送金元残高」（= 1 回目引き落とし後の値）を返す契約。
        expect(response.parsed_body["new_balance"]).to eq(400)
        expect(from_user.account.reload.balance_fuju).to eq(400)
        expect(to_user.account.reload.balance_fuju).to eq(100)
      end
    end

    context "異常系" do
      it "残高不足で 422 INSUFFICIENT_BALANCE（記帳されず残高も不変、エラー応答に new_balance を漏らさない）" do
        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 1_000 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig("error", "code")).to eq("INSUFFICIENT_BALANCE")
        expect(response.parsed_body).not_to(have_key("new_balance"))
        expect(from_user.account.reload.balance_fuju).to eq(500)
        expect(to_user.account.reload.balance_fuju).to eq(0)
      end

      it "to_user_id が current_user.external_user_id と同一で 400 VALIDATION_FAILED" do
        post_transfer(params: { to_user_id: from_user.external_user_id, amount: 10 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "to_user_id 欠落で 400 VALIDATION_FAILED" do
        post_transfer(params: { amount: 100 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "to_user_id が空文字で 400 VALIDATION_FAILED" do
        post_transfer(params: { to_user_id: "", amount: 100 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "to_user_id が ULID 形式違反で 400 VALIDATION_FAILED" do
        post_transfer(params: { to_user_id: "not-a-ulid", amount: 100 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "amount=0 で 400 VALIDATION_FAILED" do
        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 0 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "amount=-10 で 400 VALIDATION_FAILED" do
        post_transfer(params: { to_user_id: to_user.external_user_id, amount: -10 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "Idempotency-Key 未指定で 400 VALIDATION_FAILED" do
        post("/ledger/transfer", params: { ledger: { to_user_id: to_user.external_user_id, amount: 100 } })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end
    end

    context "認証ポリシー" do
      it "introspection active=false で 401 TOKEN_INACTIVE（記帳されない）" do
        stub_inactive_introspection

        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 100 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("TOKEN_INACTIVE")
        expect(from_user.account.reload.balance_fuju).to eq(500)
      end

      it "introspection が 5xx で 503 AUTHCORE_UNAVAILABLE（記帳されない）" do
        stub_introspection_server_error

        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 100 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body.dig("error", "code")).to eq("AUTHCORE_UNAVAILABLE")
      end

      it "introspection の sub がローカル JWT の sub と食い違うと 401 UNAUTHENTICATED" do
        stub_active_introspection(sub: "01HYZ9999999999999999999ZZ")

        expect do
          post_transfer(params: { to_user_id: to_user.external_user_id, amount: 100 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
      end

      it "無効 JWT では introspection が呼ばれずに 401 UNAUTHENTICATED を返す", :skip_default_auth do
        stub = stub_active_introspection

        post(
          "/ledger/transfer",
          params: { ledger: { to_user_id: to_user.external_user_id, amount: 100 } },
          headers: headers.merge("Authorization" => "Bearer invalid-token"),
        )

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
        expect(stub).not_to have_been_requested
      end
    end
  end
end
