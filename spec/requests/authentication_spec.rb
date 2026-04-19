require "rails_helper"

RSpec.describe "Authentication", :skip_default_auth, type: :request do
  before do
    Rails.application.routes.draw do
      get "/testing_authentication/whoami" => "testing_authentication#whoami"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  let!(:sub) { "01HYZ0000000000000000000AA" }

  describe "正常系" do
    it "有効な JWT で 200 を返し current_external_user_id に sub が入る" do
      get("/testing_authentication/whoami", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("external_user_id" => sub)
    end
  end

  describe "異常系" do
    shared_examples "401 UNAUTHENTICATED" do
      it "401 を返し code: UNAUTHENTICATED になる" do
        get("/testing_authentication/whoami", headers: headers)

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
      end
    end

    context "Authorization ヘッダなし" do
      let!(:headers) { {} }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "Bearer 以外のスキーム" do
      let!(:headers) { { "Authorization" => "Basic dXNlcjpwYXNz" } }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "Bearer の後にトークンがない" do
      let!(:headers) { { "Authorization" => "Bearer " } }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "別の鍵で署名された JWT" do
      let!(:other_key) { OpenSSL::PKey::RSA.new(2048) }
      let!(:headers) { auth_headers(sub: sub, key: other_key) }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "exp が過去" do
      let!(:headers) { auth_headers(sub: sub, exp: 1.minute.ago) }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "type が refresh" do
      let!(:headers) { auth_headers(sub: sub, type: "refresh") }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "aud が不一致" do
      let!(:headers) { auth_headers(sub: sub, aud: "other") }

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "iss が不一致" do
      let!(:headers) { auth_headers(sub: sub, iss: "other") }

      it_behaves_like "401 UNAUTHENTICATED"
    end
  end
end
