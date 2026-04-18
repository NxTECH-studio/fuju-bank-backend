require "rails_helper"

RSpec.describe "Artifacts", type: :request do
  describe "POST /artifacts" do
    let!(:user) { create(:user) }

    context "正常系" do
      it "physical Artifact を作成し 201 を返す" do
        expect do
          post("/artifacts", params: { artifact: { user_id: user.id, title: "油絵1号", location_kind: "physical" } })
        end.to change { Artifact.count }.by(1)

        expect(response).to have_http_status(:created)
        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[id user_id title location_kind location_url created_at])
        expect(parsed).to include(
          "user_id" => user.id,
          "title" => "油絵1号",
          "location_kind" => "physical",
          "location_url" => nil,
        )
        expect(parsed["id"]).to be_present
        expect(parsed["created_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      it "url Artifact を作成し 201 を返す" do
        expect do
          post(
            "/artifacts",
            params: {
              artifact: {
                user_id: user.id,
                title: "デジタル1号",
                location_kind: "url",
                location_url: "https://example.com/art/1",
              },
            },
          )
        end.to change { Artifact.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to include(
          "title" => "デジタル1号",
          "location_kind" => "url",
          "location_url" => "https://example.com/art/1",
        )
      end
    end

    context "異常系" do
      it "location_kind が不正なとき 422 VALIDATION_FAILED を返す" do
        expect do
          post("/artifacts", params: { artifact: { user_id: user.id, title: "x", location_kind: "invalid" } })
        end.not_to(change { Artifact.count })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end

      it "user_id が存在しないとき 422 VALIDATION_FAILED を返す" do
        expect do
          post("/artifacts", params: { artifact: { user_id: 999_999, title: "x", location_kind: "physical" } })
        end.not_to(change { Artifact.count })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      end
    end
  end

  describe "GET /artifacts/:id" do
    context "正常系" do
      let!(:user) { create(:user) }
      let!(:artifact) { create(:artifact, user: user, title: "油絵1号", location_kind: "physical") }

      it "200 と Artifact 情報を返す" do
        get("/artifacts/#{artifact.id}")

        expect(response).to have_http_status(:ok)
        parsed = response.parsed_body
        expect(parsed.keys).to match_array(%w[id user_id title location_kind location_url created_at])
        expect(parsed).to include(
          "id" => artifact.id,
          "user_id" => user.id,
          "title" => "油絵1号",
          "location_kind" => "physical",
          "location_url" => nil,
        )
      end
    end

    context "異常系" do
      it "存在しない ID のとき 404 NOT_FOUND を返す" do
        get("/artifacts/999999")

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
      end
    end
  end
end
