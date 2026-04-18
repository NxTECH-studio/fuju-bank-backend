require "rails_helper"

RSpec.describe "Ledger Mint", type: :request do
  let!(:system_account) { create(:account, :system_issuance) }
  let!(:user) { create(:user) }
  let!(:artifact) { create(:artifact, user: user) }
  let!(:idempotency_key) { "mint-key-12345" }
  let!(:headers) { { "Idempotency-Key" => idempotency_key } }

  def post_mint(params:, headers: self.headers)
    post("/ledger/mint", params: { ledger: params }, headers: headers)
  end

  describe "POST /ledger/mint" do
    context "正常系" do
      it "200 で記帳され、user 残高 +N / system_issuance 残高 -N" do
        expect do
          post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 100 })
        end.to change { LedgerTransaction.count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(user.account.reload.balance_fuju).to eq(100)
        expect(system_account.reload.balance_fuju).to eq(-100)
      end

      it "レスポンスボディに tx の主要フィールドが含まれる" do
        post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 50 })

        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[id kind artifact_id idempotency_key memo metadata occurred_at created_at])
        expect(parsed).to include(
          "kind" => "mint",
          "artifact_id" => artifact.id,
          "idempotency_key" => idempotency_key,
        )
        expect(parsed["occurred_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      it "metadata にネスト Hash を渡すと JSONB にそのまま保存される" do
        metadata = { "dwell_seconds" => 42, "gaze" => { "intensity" => 0.9 } }
        post(
          "/ledger/mint",
          params: { ledger: { artifact_id: artifact.id, user_id: user.id, amount: 10, metadata: metadata } }.to_json,
          headers: headers.merge("Content-Type" => "application/json"),
        )

        expect(response).to have_http_status(:ok)
        tx = LedgerTransaction.last
        expect(tx.metadata).to eq(metadata)
        expect(response.parsed_body["metadata"]).to eq(metadata)
      end

      it "occurred_at を渡さない場合 Time.current が保存される" do
        travel_to Time.zone.local(2026, 4, 18, 10, 0, 0) do
          post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 10 })

          expect(response).to have_http_status(:ok)
          expect(LedgerTransaction.last.occurred_at).to eq(Time.current)
        end
      end

      it "occurred_at に ISO8601 を渡すとその時刻で保存される" do
        iso = "2026-04-17T12:34:56+09:00"
        post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 10, occurred_at: iso })

        expect(response).to have_http_status(:ok)
        expect(LedgerTransaction.last.occurred_at).to eq(Time.zone.parse(iso))
      end

      it "occurred_at が空文字列の場合は Time.current にフォールバックする" do
        travel_to Time.zone.local(2026, 4, 18, 9, 0, 0) do
          post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 10, occurred_at: "" })

          expect(response).to have_http_status(:ok)
          expect(LedgerTransaction.last.occurred_at).to eq(Time.current)
        end
      end

      it "metadata 未指定の場合は空 Hash が保存される" do
        post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 10 })

        expect(response).to have_http_status(:ok)
        expect(LedgerTransaction.last.metadata).to eq({})
      end

      it "amount が文字列 '100' として渡されても 100 ふじゅ〜として記帳される" do
        post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: "100" })

        expect(response).to have_http_status(:ok)
        expect(user.account.reload.balance_fuju).to eq(100)
      end
    end

    context "冪等性" do
      it "同一 Idempotency-Key で 2 回 POST しても 1 件だけ作成され、2 回目も 200 で既存を返す" do
        post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 100 })
        first_id = response.parsed_body["id"]

        expect do
          post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 100 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(first_id)
        expect(user.account.reload.balance_fuju).to eq(100)
      end
    end

    context "異常系" do
      it "Idempotency-Key 未指定で 400 VALIDATION_FAILED" do
        post("/ledger/mint", params: { ledger: { artifact_id: artifact.id, user_id: user.id, amount: 100 } })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "amount=0 で 400 VALIDATION_FAILED（記帳されない）" do
        expect do
          post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: 0 })
        end.not_to(change { LedgerTransaction.count })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "amount=-10 で 400 VALIDATION_FAILED" do
        post_mint(params: { artifact_id: artifact.id, user_id: user.id, amount: -10 })

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "artifact_id が存在しないとき 404 NOT_FOUND" do
        post_mint(params: { artifact_id: 999_999, user_id: user.id, amount: 100 })

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
      end

      it "user_id が存在しないとき 404 NOT_FOUND" do
        post_mint(params: { artifact_id: artifact.id, user_id: 999_999, amount: 100 })

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
      end
    end
  end
end
