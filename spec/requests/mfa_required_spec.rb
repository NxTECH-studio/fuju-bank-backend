require "rails_helper"

RSpec.describe "MfaRequired concern", type: :request do
  let!(:sub) { "01HYZ0000000000000000000AA" }

  before do
    Rails.application.routes.draw do
      get "/testing_mfa/show" => "testing_mfa#show"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  context "mfa_verified=true" do
    before { stub_active_introspection(sub: sub, mfa_verified: true) }

    it "200 を返す" do
      get("/testing_mfa/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("ok" => true)
    end
  end

  context "mfa_verified=false" do
    before { stub_active_introspection(sub: sub, mfa_verified: false) }

    it "403 + MFA_REQUIRED を返す" do
      get("/testing_mfa/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("MFA_REQUIRED")
    end
  end

  context "mfa_verified が nil" do
    before { stub_active_introspection(sub: sub, mfa_verified: nil) }

    it "403 + MFA_REQUIRED を返す" do
      get("/testing_mfa/show", headers: auth_headers(sub: sub))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("MFA_REQUIRED")
    end
  end
end
