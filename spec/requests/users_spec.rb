require "rails_helper"

RSpec.describe "Users", type: :request do
  describe "POST /users" do
    context "正常系" do
      it "User と Account を 1 件ずつ作成し 201 を返す" do
        expect { post("/users", params: { user: { name: "Alice" } }) }
          .to change { User.count }.by(1)
          .and change { Account.count }.by(1)

        expect(response).to have_http_status(:created)
        parsed = response.parsed_body
        expect(parsed).to include(
          "name" => "Alice",
          "balance_fuju" => 0,
          "public_key" => nil,
        )
        expect(parsed["id"]).to be_present
        expect(parsed["created_at"]).to be_present
      end

      it "public_key を指定した場合もレスポンスに反映される" do
        post("/users", params: { user: { name: "Bob", public_key: "pk_abc" } })

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to include("name" => "Bob", "public_key" => "pk_abc")
      end
    end

    context "異常系" do
      it "name が空のとき 422 VALIDATION_FAILED を返す" do
        expect { post("/users", params: { user: { name: "" } }) }
          .not_to(change { User.count })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end
    end
  end
end
