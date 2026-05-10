require "rails_helper"

RSpec.describe "GET /users/lookup", type: :request do
  let!(:default_sub) { "01HYZ0000000000000000000AA" }
  let!(:caller_user) { create(:user, external_user_id: default_sub, public_id: "me_caller") }

  before { stub_active_introspection(sub: default_sub) }

  context "正常系" do
    let!(:target) { create(:user, name: "アリス", public_id: "alice") }

    it "200 と DTO（id / public_id / name / icon_url）を返す" do
      get("/users/lookup", params: { public_id: "alice" })

      expect(response).to have_http_status(:ok)
      parsed = response.parsed_body
      expect(parsed.keys).to match_array(%w[id public_id name icon_url])
      expect(parsed).to include(
        "id" => target.id,
        "public_id" => "alice",
        "name" => "アリス",
        "icon_url" => nil,
      )
    end

    it "balance_fuju や public_key などのプライベート情報は返さない" do
      target.account.update!(balance_fuju: 1234)
      target.update!(public_key: "pk_secret")

      get("/users/lookup", params: { public_id: "alice" })

      parsed = response.parsed_body
      expect(parsed).not_to have_key("balance_fuju")
      expect(parsed).not_to have_key("public_key")
      expect(parsed).not_to have_key("created_at")
    end

    it "自分自身を lookup しても 200 を返す（クライアント側で自分宛を弾く責務）" do
      get("/users/lookup", params: { public_id: caller_user.public_id })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => caller_user.id, "public_id" => caller_user.public_id)
    end
  end

  context "存在しない public_id" do
    it "404 NOT_FOUND を返す" do
      get("/users/lookup", params: { public_id: "ghost" })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
    end
  end

  context "バリデーション" do
    it "public_id 未指定なら 400 VALIDATION_FAILED" do
      get("/users/lookup")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "空文字なら 400 VALIDATION_FAILED" do
      get("/users/lookup", params: { public_id: "" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "33 文字なら 400 VALIDATION_FAILED" do
      get("/users/lookup", params: { public_id: "a" * 33 })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "不正文字（マルチバイト）なら 400 VALIDATION_FAILED" do
      get("/users/lookup", params: { public_id: "アリス" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end
  end

  context "認証" do
    it "Authorization ヘッダがない場合 401 UNAUTHENTICATED", :skip_default_auth do
      get("/users/lookup", params: { public_id: "alice" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
    end

    it "introspection inactive なら 401 TOKEN_INACTIVE" do
      stub_inactive_introspection

      get("/users/lookup", params: { public_id: "alice" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("TOKEN_INACTIVE")
    end
  end
end
