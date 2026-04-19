require "rails_helper"

RSpec.describe "IntrospectionRequired concern", type: :request do
  let!(:sub) { "01HYZ0000000000000000000AA" }

  before do
    Rails.application.routes.draw do
      get "/testing_introspection/show" => "testing_introspection#show"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  context "有効 JWT + introspection active=true + sub 一致" do
    before { stub_active_introspection(sub: sub) }

    it "200 を返し introspection 結果が参照できる" do
      get("/testing_introspection/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "external_user_id" => sub,
        "introspection_sub" => sub,
      )
    end
  end

  context "有効 JWT + introspection active=false" do
    before { stub_inactive_introspection }

    it "401 + TOKEN_INACTIVE を返す" do
      get("/testing_introspection/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("TOKEN_INACTIVE")
    end
  end

  context "有効 JWT + introspection 5xx" do
    before { stub_introspection_server_error }

    it "503 + AUTHCORE_UNAVAILABLE を返す" do
      get("/testing_introspection/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("AUTHCORE_UNAVAILABLE")
    end
  end

  context "introspection の sub がローカル JWT の sub と食い違う" do
    before { stub_active_introspection(sub: "01HYZ9999999999999999999ZZ") }

    it "401 + UNAUTHENTICATED を返す" do
      get("/testing_introspection/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
    end
  end

  context "無効 JWT", :skip_default_auth do
    it "401 + UNAUTHENTICATED を返し、introspection は呼ばれない" do
      stub = stub_active_introspection(sub: sub)

      get("/testing_introspection/show", headers: { "Authorization" => "Bearer invalid-token" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
      expect(stub).not_to have_been_requested
    end
  end
end
