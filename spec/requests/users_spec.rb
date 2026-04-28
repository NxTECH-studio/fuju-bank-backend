require "rails_helper"

RSpec.describe "Users", type: :request do
  # AuthenticatedRequest が auth_headers の既定 sub を注入する
  let!(:default_sub) { "01HYZ0000000000000000000AA" }

  describe "POST /users/me" do
    context "新規プロビジョニング" do
      it "User と Account を 1 件ずつ作成し 201 を返す" do
        expect { post("/users/me", params: { name: "Alice" }) }
          .to change { User.count }.by(1)
          .and change { Account.count }.by(1)

        expect(response).to have_http_status(:created)
        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[id name public_key balance_fuju created_at])
        expect(parsed).to include(
          "name" => "Alice",
          "balance_fuju" => 0,
          "public_key" => nil,
        )
        expect(parsed["id"]).to be_present
        expect(parsed["created_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      it "external_user_id は JWT の sub から取られる（body 値は無視される）" do
        post("/users/me", params: { external_user_id: "01HZZZZZZZZZZZZZZZZZZZZZZZ", name: "Alice" })

        expect(response).to have_http_status(:created)
        expect(User.last.external_user_id).to eq(default_sub)
      end

      it "作成された Account は kind=user / balance_fuju=0 で初期化される" do
        post("/users/me", params: { name: "Alice" })

        account = User.last.account
        expect(account.kind).to eq("user")
        expect(account.balance_fuju).to eq(0)
      end

      it "public_key を指定した場合もレスポンスに反映される" do
        post("/users/me", params: { name: "Bob", public_key: "pk_abc" })

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to include("name" => "Bob", "public_key" => "pk_abc")
      end

      it "name 未指定でも 201 を返す" do
        expect { post("/users/me") }
          .to change { User.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to include("name" => nil)
      end
    end

    context "既存（idempotent）" do
      let!(:existing_user) { create(:user, external_user_id: default_sub, name: "Original", public_key: "pk_original") }

      it "二度目以降は User を増やさず 200 を返す" do
        expect { post("/users/me", params: { name: "Updated" }) }
          .not_to(change { User.count })

        expect(response).to have_http_status(:ok)
      end

      it "既存ユーザーの属性は body 値で上書きされない" do
        post("/users/me", params: { name: "Updated", public_key: "pk_updated" })

        expect(existing_user.reload).to have_attributes(name: "Original", public_key: "pk_original")
        expect(response.parsed_body).to include("name" => "Original", "public_key" => "pk_original")
      end
    end

    context "認証" do
      it "Authorization ヘッダがない場合 401 を返す", :skip_default_auth do
        post("/users/me", params: { name: "Alice" })

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
      end
    end
  end

  describe "GET /users/me" do
    context "プロビジョニング済み" do
      let!(:user) { create(:user, external_user_id: default_sub, name: "Alice", public_key: "pk_abc") }

      it "200 と User 情報を返す" do
        get("/users/me")

        expect(response).to have_http_status(:ok)
        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[id name public_key balance_fuju created_at])
        expect(parsed).to include(
          "id" => user.id,
          "name" => "Alice",
          "public_key" => "pk_abc",
          "balance_fuju" => 0,
        )
      end

      it "account.balance_fuju の値を反映する" do
        user.account.update!(balance_fuju: 1234)

        get("/users/me")

        expect(response.parsed_body).to include("balance_fuju" => 1234)
      end
    end

    context "未プロビジョニング" do
      it "401 UNAUTHENTICATED を返す" do
        get("/users/me")

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
      end
    end
  end

  describe "GET /users/:id" do
    context "自分の id" do
      let!(:user) { create(:user, external_user_id: default_sub, name: "Alice", public_key: "pk_abc") }

      it "200 と User 情報・残高を返す" do
        get("/users/#{user.id}")

        expect(response).to have_http_status(:ok)
        parsed = response.parsed_body
        expect(parsed).to include(
          "id" => user.id,
          "name" => "Alice",
          "public_key" => "pk_abc",
          "balance_fuju" => 0,
        )
      end

      it "account.balance_fuju の値を反映する" do
        user.account.update!(balance_fuju: 1234)

        get("/users/#{user.id}")

        expect(response.parsed_body).to include("balance_fuju" => 1234)
      end

      it "参照系では AuthCore introspection が呼ばれない" do
        stub = stub_active_introspection

        get("/users/#{user.id}")

        expect(response).to have_http_status(:ok)
        expect(stub).not_to have_been_requested
      end
    end

    context "他人の id" do
      let!(:me) { create(:user, external_user_id: default_sub) }
      let!(:other) { create(:user, external_user_id: "01HYZ0000000000000000000BB") }

      it "403 FORBIDDEN を返す" do
        get("/users/#{other.id}")

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig("error", "code")).to eq("FORBIDDEN")
      end
    end

    context "存在しない id" do
      let!(:me) { create(:user, external_user_id: default_sub) }

      it "他人扱いとして 403 FORBIDDEN を返す" do
        get("/users/999999")

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig("error", "code")).to eq("FORBIDDEN")
      end
    end

    context "未プロビジョニング" do
      let!(:other) { create(:user, external_user_id: "01HYZ0000000000000000000BB") }

      it "401 UNAUTHENTICATED を返す" do
        get("/users/#{other.id}")

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
      end
    end
  end
end
