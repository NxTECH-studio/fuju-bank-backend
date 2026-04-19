require "rails_helper"

RSpec.describe "Authentication", :skip_default_auth, type: :request do
  before do
    Rails.application.routes.draw do
      get "/testing_authentication/whoami" => "testing_authentication#whoami"
      get "/testing_authentication/me" => "testing_authentication#me"
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

  describe "lazy user プロビジョニング" do
    it "新規 sub の JWT で /me を叩くと User が 1 件生えて 200 を返す" do
      expect do
        get("/testing_authentication/me", headers: auth_headers(sub: sub))
      end.to change { User.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["external_user_id"]).to eq(sub)
    end

    it "同じ sub で 2 回目のリクエストは User は増えない" do
      get("/testing_authentication/me", headers: auth_headers(sub: sub))

      expect do
        get("/testing_authentication/me", headers: auth_headers(sub: sub))
      end.not_to(change { User.count })

      expect(response).to have_http_status(:ok)
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

    context "alg=none（署名なし）" do
      let!(:headers) do
        payload = { sub: sub, type: "access", aud: "authcore", iss: "authcore", exp: 5.minutes.from_now.to_i }
        { "Authorization" => "Bearer #{JWT.encode(payload, nil, 'none')}" }
      end

      it_behaves_like "401 UNAUTHENTICATED"
    end

    # alg=RS256 期待の検証器に、公開鍵を HMAC キーとして署名した alg=HS256 JWT を渡す古典攻撃。
    context "alg=HS256 で公開鍵を HMAC キーに使った confused deputy 攻撃" do
      let!(:headers) do
        payload = { sub: sub, type: "access", aud: "authcore", iss: "authcore", exp: 5.minutes.from_now.to_i }
        token = JWT.encode(payload, TestKeypair.public_key_pem, "HS256")
        { "Authorization" => "Bearer #{token}" }
      end

      it_behaves_like "401 UNAUTHENTICATED"
    end

    context "sub クレームが欠落" do
      let!(:headers) do
        payload = { type: "access", aud: "authcore", iss: "authcore", exp: 5.minutes.from_now.to_i }
        { "Authorization" => "Bearer #{JWT.encode(payload, test_private_key, 'RS256')}" }
      end

      it_behaves_like "401 UNAUTHENTICATED"
    end
  end
end
