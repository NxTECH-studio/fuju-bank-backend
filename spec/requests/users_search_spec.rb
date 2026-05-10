require "rails_helper"

RSpec.describe "GET /users/search", type: :request do
  let!(:default_sub) { "01HYZ0000000000000000000AA" }
  let!(:caller_user) { create(:user, external_user_id: default_sub, public_id: "me_caller") }

  before { stub_active_introspection(sub: default_sub) }

  context "正常系" do
    let!(:alice1) { create(:user, public_id: "alice") }
    let!(:alice2) { create(:user, public_id: "alice2024") }
    let!(:bob) { create(:user, public_id: "bob") }

    it "200 と { users: [...] } を返し、各要素は id / public_id / icon_url のみ（name は含まれない）" do
      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:ok)
      parsed = response.parsed_body
      expect(parsed.keys).to eq(%w[users])
      expect(parsed["users"].size).to eq(2)
      parsed["users"].each do |hit|
        expect(hit.keys).to match_array(%w[id public_id icon_url])
        expect(hit["icon_url"]).to be_nil
      end
    end

    it "前方一致でヒットする（ali → alice / alice2024）" do
      get("/users/search", params: { q: "ali" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(alice1.id, alice2.id)
    end

    it "完全一致も前方一致仕様の中でヒットする（alice → alice / alice2024）" do
      get("/users/search", params: { q: "alice" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(alice1.id, alice2.id)
    end

    it "大文字小文字無視（ALI → alice / alice2024）" do
      get("/users/search", params: { q: "ALI" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(alice1.id, alice2.id)
    end

    it "中間一致では拾わない（lice → 0 件）" do
      get("/users/search", params: { q: "lice" })

      expect(response.parsed_body["users"]).to eq([])
    end

    it "ハイフンを含む public_id も前方一致でヒットする" do
      hyphen = create(:user, public_id: "ali-ce")

      get("/users/search", params: { q: "ali-" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(hyphen.id)
    end

    it "public_id が NULL のレコードはヒットしない" do
      create(:user, public_id: nil)

      get("/users/search", params: { q: "ali" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(alice1.id, alice2.id)
    end

    it "ヒット 0 件は 200 + 空配列を返す（404 ではない）" do
      get("/users/search", params: { q: "zzz" })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("users" => [])
    end

    it "自分自身は API 側で除外される（自分の public_id でも検索結果に含まれない）" do
      get("/users/search", params: { q: caller_user.public_id })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).not_to include(caller_user.id)
    end

    it "balance_fuju や public_key などのプライベート情報は返さない" do
      alice1.account.update!(balance_fuju: 1234)
      alice1.update!(public_key: "pk_secret")

      get("/users/search", params: { q: "ali" })

      hit = response.parsed_body["users"].find { |u| u["id"] == alice1.id }
      expect(hit).not_to have_key("balance_fuju")
      expect(hit).not_to have_key("public_key")
      expect(hit).not_to have_key("created_at")
      expect(hit).not_to have_key("name")
    end
  end

  context "limit" do
    let!(:targets) { Array.new(21) { |i| create(:user, public_id: format("sample%02d", i)) } }

    it "デフォルト 10 件返す" do
      get("/users/search", params: { q: "sample" })

      expect(response.parsed_body["users"].size).to eq(10)
    end

    it "明示指定の limit を尊重する" do
      get("/users/search", params: { q: "sample", limit: 5 })

      expect(response.parsed_body["users"].size).to eq(5)
    end

    it "上限 (20) ちょうどは valid" do
      get("/users/search", params: { q: "sample", limit: 20 })

      expect(response.parsed_body["users"].size).to eq(20)
    end

    it "id 昇順で先頭から limit 件返す" do
      get("/users/search", params: { q: "sample", limit: 3 })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to eq(targets.first(3).map(&:id))
    end
  end

  context "SQL ワイルドカードのエスケープ" do
    let!(:u_plain) { create(:user, public_id: "u_plain") }
    let!(:u_test) { create(:user, public_id: "u_test") }
    let!(:ux_other) { create(:user, public_id: "uxother") }

    it "_ を含むクエリは literal として扱う（任意 1 文字のワイルドカードにならない）" do
      get("/users/search", params: { q: "u_" })

      ids = response.parsed_body["users"].pluck("id")
      expect(ids).to contain_exactly(u_plain.id, u_test.id)
    end

    # public_id 自体は PUBLIC_ID_REGEX で `%` を許可しないが、検索クエリ q では入りうる。
    # サニタイズが外れると `q="a%"` で全 a* 列挙が可能になり enumeration 抑止が崩れるので守る。
    it "% を含むクエリは literal として扱う（任意 0 文字以上のワイルドカードにならない）" do
      get("/users/search", params: { q: "u%" })

      expect(response.parsed_body["users"]).to eq([])
    end
  end

  context "境界値（valid な長さ）" do
    let!(:targets) { Array.new(2) { |i| create(:user, public_id: format("ab%02d", i)) } }

    it "q が 2 文字ちょうどなら 200" do
      get("/users/search", params: { q: "ab" })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["users"].size).to eq(2)
    end

    it "q が 64 文字ちょうどなら 200（ヒット 0 件でもバリデーションは通る）" do
      get("/users/search", params: { q: "a" * 64 })

      expect(response).to have_http_status(:ok)
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

    it "q が 65 文字なら 400 VALIDATION_FAILED" do
      get("/users/search", params: { q: "a" * 65 })

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
      get("/users/search", params: { q: "ali" })

      expect(response).to have_http_status(:ok)
    end
  end
end
