require "rails_helper"
require "base64"

RSpec.describe Authcore::IntrospectionClient do
  let!(:base_url) { "https://auth.fuju.example" }
  let!(:client_id) { "bank-client" }
  let!(:client_secret) { "s3cret" }
  let!(:token) { "access-token.jwt.value" }
  let!(:endpoint) { "#{base_url}/v1/auth/introspect" }
  let!(:expected_basic_auth) do
    "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
  end
  let!(:expected_body) { "token=#{token}&token_type_hint=access_token" }

  before do
    stub_const(
      "ENV",
      ENV.to_hash.merge(
        "AUTHCORE_BASE_URL" => base_url,
        "AUTHCORE_CLIENT_ID" => client_id,
        "AUTHCORE_CLIENT_SECRET" => client_secret,
      ),
    )
  end

  describe ".call" do
    context "200 + active=true の場合" do
      let!(:payload) do
        {
          "active" => true,
          "sub" => "01HXSUBULID",
          "client_id" => "bank-client",
          "username" => "alice",
          "token_type" => "access_token",
          "mfa_verified" => true,
          "aud" => "authcore",
          "exp" => 1_900_000_000,
          "iat" => 1_800_000_000,
        }
      end

      before do
        stub_request(:post, endpoint).to_return(
          status: 200,
          body: payload.to_json,
          headers: { "Content-Type" => "application/json" },
        )
      end

      it "IntrospectionResult を返す" do
        result = described_class.call(token: token)

        expect(result).to be_a(Authcore::IntrospectionResult)
        expect(result).to be_active
        expect(result.sub).to eq("01HXSUBULID")
        expect(result.client_id).to eq("bank-client")
        expect(result.username).to eq("alice")
        expect(result.token_type).to eq("access_token")
        expect(result).to be_mfa_verified
        expect(result.aud).to eq("authcore")
        expect(result.exp).to eq(1_900_000_000)
        expect(result.iat).to eq(1_800_000_000)
      end

      it "Basic 認証 / form-urlencoded body で呼び出す" do
        described_class.call(token: token)

        expect(WebMock).to have_requested(:post, endpoint)
          .with(
            headers: {
              "Authorization" => expected_basic_auth,
              "Content-Type" => "application/x-www-form-urlencoded",
            },
            body: expected_body,
          )
      end
    end

    context "200 + active=false の場合" do
      before do
        stub_request(:post, endpoint).to_return(
          status: 200,
          body: { "active" => false }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
      end

      it "TokenInactiveError を raise する" do
        expect { described_class.call(token: token) }.to raise_error(TokenInactiveError)
      end
    end

    context "401 (client 認証失敗) の場合" do
      before do
        stub_request(:post, endpoint).to_return(status: 401, body: "")
      end

      it "AuthcoreUnavailableError を raise する" do
        expect { described_class.call(token: token) }.to raise_error(AuthcoreUnavailableError)
      end
    end

    context "500 の場合" do
      before do
        stub_request(:post, endpoint).to_return(status: 500, body: "")
      end

      it "AuthcoreUnavailableError を raise する" do
        expect { described_class.call(token: token) }.to raise_error(AuthcoreUnavailableError)
      end
    end

    context "タイムアウトの場合" do
      before do
        stub_request(:post, endpoint).to_timeout
      end

      it "AuthcoreUnavailableError を raise する" do
        expect { described_class.call(token: token) }.to raise_error(AuthcoreUnavailableError)
      end
    end

    context "接続失敗の場合" do
      before do
        stub_request(:post, endpoint).to_raise(Errno::ECONNREFUSED)
      end

      it "AuthcoreUnavailableError を raise する" do
        expect { described_class.call(token: token) }.to raise_error(AuthcoreUnavailableError)
      end
    end

    context "JSON が不正な場合" do
      before do
        stub_request(:post, endpoint).to_return(
          status: 200,
          body: "not-json",
          headers: { "Content-Type" => "application/json" },
        )
      end

      it "AuthcoreUnavailableError を raise する" do
        expect { described_class.call(token: token) }
          .to raise_error(AuthcoreUnavailableError, /解釈できません/)
      end
    end
  end
end
