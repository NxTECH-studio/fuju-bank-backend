require "rails_helper"

RSpec.describe "GET /users/search", type: :request do
  let!(:default_sub) { "01HYZ0000000000000000000AA" }
  let!(:caller_user) { create(:user, external_user_id: default_sub, public_id: "mecaller") }

  before { stub_active_introspection(sub: default_sub) }

  def authcore_user(id:, public_id:, icon_url: nil)
    { "id" => id, "public_id" => public_id, "icon_url" => icon_url }
  end

  context "正常系" do
    let!(:alice1) { authcore_user(id: "01HALICE000000000000000000", public_id: "alice", icon_url: "https://cdn.example/alice.webp") }
    let!(:alice2) { authcore_user(id: "01HALICIA00000000000000000", public_id: "alice2024") }

    before { stub_authcore_user_search(query: "ali", users: [alice1, alice2]) }

    it "200 と { users: [...] } を返し、各要素は id / public_id / icon_url のみ" do
      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:ok)
      parsed = response.parsed_body
      expect(parsed.keys).to eq(%w[users])
      expect(parsed["users"].size).to eq(2)
      parsed["users"].each do |hit|
        expect(hit.keys).to match_array(%w[id public_id icon_url])
      end
    end

    it "AuthCore 結果の id / public_id / icon_url がそのまま伝搬する" do
      get("/users/search", params: { q: "ali" })

      hits = response.parsed_body["users"]
      expect(hits).to contain_exactly(
        { "id" => alice1["id"], "public_id" => "alice", "icon_url" => "https://cdn.example/alice.webp" },
        { "id" => alice2["id"], "public_id" => "alice2024", "icon_url" => nil },
      )
    end

    it "ヒット 0 件は 200 + 空配列を返す（404 ではない）" do
      stub_authcore_user_search(query: "zzz", users: [])

      get("/users/search", params: { q: "zzz" })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("users" => [])
    end

    it "AuthCore へ q と limit (デフォルト 10) を送る" do
      get("/users/search", params: { q: "ali" })

      expect(WebMock).to have_requested(:get, AuthcoreUserSearchStubs::USER_SEARCH_ENDPOINT)
        .with(query: { q: "ali", limit: "10" })
    end

    it "明示指定の limit を AuthCore に渡す" do
      stub_authcore_user_search(query: "ali", limit: 5, users: [alice1])

      get("/users/search", params: { q: "ali", limit: 5 })

      expect(WebMock).to have_requested(:get, AuthcoreUserSearchStubs::USER_SEARCH_ENDPOINT)
        .with(query: { q: "ali", limit: "5" })
    end
  end

  context "自己除外" do
    it "自分の external_user_id (= AuthCore id) は結果から除外される" do
      self_hit = { "id" => default_sub, "public_id" => "mecaller", "icon_url" => nil }
      other = { "id" => "01HOTHER0000000000000000AA", "public_id" => "metro", "icon_url" => nil }
      stub_authcore_user_search(query: "me", users: [self_hit, other])

      get("/users/search", params: { q: "me" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(other["id"])
    end

    it "自己ヒットしか無い場合は空配列になる" do
      self_hit = { "id" => default_sub, "public_id" => "mecaller", "icon_url" => nil }
      stub_authcore_user_search(query: "mecaller", users: [self_hit])

      get("/users/search", params: { q: "mecaller" })

      expect(response.parsed_body).to eq("users" => [])
    end
  end

  context "境界値（valid な長さ・limit）" do
    before { stub_authcore_user_search(users: []) }

    it "q が 2 文字ちょうどなら 200" do
      get("/users/search", params: { q: "ab" })

      expect(response).to have_http_status(:ok)
    end

    it "q が 32 文字ちょうどなら 200" do
      get("/users/search", params: { q: "a" * 32 })

      expect(response).to have_http_status(:ok)
    end

    it "limit が 1 なら 200" do
      get("/users/search", params: { q: "ali", limit: 1 })

      expect(response).to have_http_status(:ok)
    end

    it "limit が 20 なら 200（上限ちょうど）" do
      get("/users/search", params: { q: "ali", limit: 20 })

      expect(response).to have_http_status(:ok)
    end

    it "q の前後空白は strip され、strip 後の値で AuthCore を呼ぶ" do
      get("/users/search", params: { q: "  ali  " })

      expect(WebMock).to have_requested(:get, AuthcoreUserSearchStubs::USER_SEARCH_ENDPOINT)
        .with(query: { q: "ali", limit: "10" })
    end
  end

  context "バリデーション" do
    it "q 未指定なら 400 VALIDATION_FAILED" do
      get("/users/search")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "q が空文字なら 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "q が空白のみ（trim 後 0 文字）なら 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "   " })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "q が 1 文字なら 400 VALIDATION_FAILED（最低 2 文字）" do
      get("/users/search", params: { q: "A" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "q が 33 文字なら 400 VALIDATION_FAILED（最大 32 文字）" do
      get("/users/search", params: { q: "a" * 33 })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    # AuthCore /v1/users/search は alphanumeric のみ受け付けるので bank で先回り 400 にする。
    it "q に `_` を含む場合 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "a_b" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "q に `-` を含む場合 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "a-b" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "q に `%` を含む場合 400 VALIDATION_FAILED（enumeration 抑止のため AuthCore に投げない）" do
      get("/users/search", params: { q: "a%" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "limit が 0 なら 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "ali", limit: 0 })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "limit が 21 なら 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "ali", limit: 21 })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end

    it "limit が非数値なら 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "ali", limit: "abc" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
    end
  end

  context "認証" do
    it "Authorization ヘッダがない場合 401 UNAUTHENTICATED", :skip_default_auth do
      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("UNAUTHENTICATED")
    end

    it "introspection inactive なら 401 TOKEN_INACTIVE" do
      stub_inactive_introspection

      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("TOKEN_INACTIVE")
    end

    # 既定の stub_active_introspection は mfa_verified=false。
    # 後続改修で誤って MfaRequired を足したときに気付くため。
    it "MFA 未済（mfa_verified=false）でも 200 を返す" do
      stub_authcore_user_search(query: "ali", users: [])

      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:ok)
    end
  end

  context "AuthCore 障害" do
    it "AuthCore が 500 を返したら 503 AUTHCORE_UNAVAILABLE" do
      stub_authcore_user_search_error(status: 500)

      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("AUTHCORE_UNAVAILABLE")
    end

    it "AuthCore が timeout したら 503 AUTHCORE_UNAVAILABLE" do
      stub_authcore_user_search_timeout

      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("AUTHCORE_UNAVAILABLE")
    end
  end
end
