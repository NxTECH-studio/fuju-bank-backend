require "rails_helper"

RSpec.describe "Ledger Transfer", type: :request do
  let!(:system_account) { create(:account, :system_issuance) }
  let!(:from_user) { create(:user) }
  let!(:to_user) { create(:user) }
  let!(:idempotency_key) { "transfer-key-12345" }
  let!(:headers) { { "Idempotency-Key" => idempotency_key } }

  before do
    from_user.account.update!(balance_fuju: 500)
  end

  def post_transfer(params:, headers: self.headers)
    post("/ledger/transfer", params: { ledger: params }, headers: headers)
  end

  describe "POST /ledger/transfer" do
    context "正常系" do
      it "200 で記帳され、from -N / to +N / system_issuance 変化なし" do
        expect do
          post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 100 })
        end.to change { LedgerTransaction.count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(from_user.account.reload.balance_fuju).to eq(400)
        expect(to_user.account.reload.balance_fuju).to eq(100)
        expect(system_account.reload.balance_fuju).to eq(0)
      end

      it "レスポンスボディに tx の主要フィールドが含まれる" do
        post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 50, memo: "thanks" })

        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[id kind artifact_id idempotency_key memo metadata occurred_at created_at])
        expect(parsed).to include(
          "kind" => "transfer",
          "artifact_id" => nil,
          "idempotency_key" => idempotency_key,
          "memo" => "thanks",
        )
        expect(parsed["occurred_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      it "metadata にネスト Hash を渡すと JSONB にそのまま保存される" do
        metadata = { "gift" => { "reason" => "birthday" } }
        post(
          "/ledger/transfer",
          params: { ledger: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 10, metadata: metadata } }.to_json,
          headers: headers.merge("Content-Type" => "application/json"),
        )

        expect(response).to have_http_status(:ok)
        tx = LedgerTransaction.last
        expect(tx.metadata).to eq(metadata)
        expect(response.parsed_body["metadata"]).to eq(metadata)
      end

      it "occurred_at を渡さない場合 Time.current が保存される" do
        travel_to Time.zone.local(2026, 4, 18, 10, 0, 0) do
          post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 10 })

          expect(response).to have_http_status(:ok)
          expect(LedgerTransaction.last.occurred_at).to eq(Time.current)
        end
      end

      it "memo 未指定の場合は nil で保存される" do
        post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 10 })

        expect(response).to have_http_status(:ok)
        expect(LedgerTransaction.last.memo).to be_nil
      end
    end

    context "冪等性" do
      it "同一 Idempotency-Key で 2 回 POST しても 1 件だけ作成され、2 回目も 200 で既存を返す" do
        post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 100 })
        first_id = response.parsed_body["id"]

        expect do
          post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 100 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(first_id)
        expect(from_user.account.reload.balance_fuju).to eq(400)
        expect(to_user.account.reload.balance_fuju).to eq(100)
      end
    end

    context "異常系" do
      it "残高不足で 422 INSUFFICIENT_BALANCE（記帳されず残高も不変）" do
        expect do
          post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 1_000 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig("error", "code")).to eq("INSUFFICIENT_BALANCE")
        expect(from_user.account.reload.balance_fuju).to eq(500)
        expect(to_user.account.reload.balance_fuju).to eq(0)
      end

      it "from_user_id == to_user_id で 400 VALIDATION_FAILED" do
        post_transfer(params: { from_user_id: from_user.id, to_user_id: from_user.id, amount: 10 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "amount=0 で 400 VALIDATION_FAILED" do
        expect do
          post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 0 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "amount=-10 で 400 VALIDATION_FAILED" do
        post_transfer(params: { from_user_id: from_user.id, to_user_id: to_user.id, amount: -10 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "Idempotency-Key 未指定で 400 VALIDATION_FAILED" do
        post("/ledger/transfer", params: { ledger: { from_user_id: from_user.id, to_user_id: to_user.id, amount: 100 } })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "from_user_id が存在しないとき 404 NOT_FOUND" do
        post_transfer(params: { from_user_id: 999_999, to_user_id: to_user.id, amount: 100 })

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
      end

      it "to_user_id が存在しないとき 404 NOT_FOUND" do
        post_transfer(params: { from_user_id: from_user.id, to_user_id: 999_999, amount: 100 })

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
      end
    end
  end
end
