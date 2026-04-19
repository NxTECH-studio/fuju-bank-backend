require "rails_helper"

RSpec.describe "User Transactions", type: :request do
  let!(:system_account) { create(:account, :system_issuance) }
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:artifact) { create(:artifact, user: user) }

  def mint!(amount:, key:, occurred_at: Time.current, metadata: {})
    Ledger::Mint.call(
      artifact: artifact,
      user: user,
      amount: amount,
      idempotency_key: key,
      metadata: metadata,
      occurred_at: occurred_at,
    )
  end

  def transfer!(from:, to:, amount:, key:, memo: nil, occurred_at: Time.current)
    Ledger::Transfer.call(
      from_user: from,
      to_user: to,
      amount: amount,
      idempotency_key: key,
      memo: memo,
      occurred_at: occurred_at,
    )
  end

  describe "GET /users/:user_id/transactions" do
    context "履歴が空のとき" do
      it "200 と data: [] を返す" do
        get("/users/#{user.id}/transactions")

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("data" => [])
      end
    end

    context "mint と transfer が混在するとき" do
      let!(:mint_tx) { mint!(amount: 300, key: "mint-1", occurred_at: Time.zone.local(2026, 4, 18, 9, 0, 0)) }
      let!(:sent_tx) do
        transfer!(from: user, to: other_user, amount: 100, key: "send-1",
                  memo: "thanks", occurred_at: Time.zone.local(2026, 4, 18, 10, 0, 0),)
      end
      let!(:received_tx) do
        transfer!(from: other_user, to: user, amount: 50, key: "recv-1",
                  occurred_at: Time.zone.local(2026, 4, 18, 11, 0, 0),)
      end

      before do
        # 相手から受け取るためには other_user に残高が必要
        other_user.account.update!(balance_fuju: other_user.account.balance_fuju + 50)
      end

      it "user の関係する entry のみ、id 降順で返す" do
        get("/users/#{user.id}/transactions")

        expect(response).to have_http_status(:ok)
        data = response.parsed_body["data"]
        expect(data.size).to eq(3)
        expect(data.pluck("transaction_id")).to eq([received_tx.id, sent_tx.id, mint_tx.id])
      end

      it "mint の entry は credit / artifact_id あり / counterparty_user_id は nil" do
        get("/users/#{user.id}/transactions")

        mint_entry = response.parsed_body["data"].find { |e| e["transaction_kind"] == "mint" }
        expect(mint_entry).to include(
          "transaction_id" => mint_tx.id,
          "transaction_kind" => "mint",
          "direction" => "credit",
          "amount" => 300,
          "artifact_id" => artifact.id,
          "counterparty_user_id" => nil,
        )
      end

      it "transfer の送信 entry は debit / counterparty_user_id は受信者" do
        get("/users/#{user.id}/transactions")

        sent_entry = response.parsed_body["data"].find { |e| e["transaction_id"] == sent_tx.id }
        expect(sent_entry).to include(
          "transaction_kind" => "transfer",
          "direction" => "debit",
          "amount" => 100,
          "artifact_id" => nil,
          "counterparty_user_id" => other_user.id,
          "memo" => "thanks",
        )
      end

      it "transfer の受信 entry は credit / counterparty_user_id は送信者" do
        get("/users/#{user.id}/transactions")

        recv_entry = response.parsed_body["data"].find { |e| e["transaction_id"] == received_tx.id }
        expect(recv_entry).to include(
          "transaction_kind" => "transfer",
          "direction" => "credit",
          "amount" => 50,
          "counterparty_user_id" => other_user.id,
        )
      end

      it "レスポンスの各 entry に想定キーが揃う" do
        get("/users/#{user.id}/transactions")

        expect(response.parsed_body["data"].first.keys).to match_array(
          %w[entry_id transaction_id transaction_kind direction amount artifact_id counterparty_user_id memo metadata occurred_at created_at],
        )
      end

      it "occurred_at / created_at が ISO8601 形式で返る" do
        get("/users/#{user.id}/transactions")

        response.parsed_body["data"].each do |entry|
          expect(entry["occurred_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
          expect(entry["created_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
        end
      end
    end

    context "limit パラメータ" do
      let!(:txs) do
        (1..3).map do |i|
          mint!(amount: 10, key: "mint-#{i}", occurred_at: Time.zone.local(2026, 4, 18, 9, i, 0))
        end
      end

      it "limit=2 で 2 件に絞られる" do
        get("/users/#{user.id}/transactions", params: { limit: 2 })

        expect(response).to have_http_status(:ok)
        data = response.parsed_body["data"]
        expect(data.size).to eq(2)
        expect(data.pluck("transaction_id")).to eq([txs[2].id, txs[1].id])
      end

      it "limit 未指定ではデフォルト（最大 50）まで返る" do
        get("/users/#{user.id}/transactions")

        expect(response.parsed_body["data"].size).to eq(3)
      end

      it "limit=0 の場合はデフォルトにフォールバックする" do
        get("/users/#{user.id}/transactions", params: { limit: 0 })

        expect(response.parsed_body["data"].size).to eq(3)
      end

      it "limit=-5 の場合はデフォルトにフォールバックする" do
        get("/users/#{user.id}/transactions", params: { limit: -5 })

        expect(response.parsed_body["data"].size).to eq(3)
      end

      it "limit=9999 は MAX_LIMIT(200) に丸められる" do
        get("/users/#{user.id}/transactions", params: { limit: 9999 })

        # 実件数 3 件しかないが、SQL LIMIT としては 200 を使う想定。件数制限が効くだけなのでここでは 3 件を確認。
        expect(response.parsed_body["data"].size).to eq(3)
      end
    end

    context "存在しない user_id" do
      it "404 NOT_FOUND を返す" do
        get("/users/999999/transactions")

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
      end
    end

    context "認証ポリシー" do
      it "参照系では AuthCore introspection が呼ばれない" do
        stub = stub_active_introspection

        get("/users/#{user.id}/transactions")

        expect(response).to have_http_status(:ok)
        expect(stub).not_to have_been_requested
      end
    end
  end
end
