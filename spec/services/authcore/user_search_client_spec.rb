require "rails_helper"
require "base64"

RSpec.describe Authcore::UserSearchClient do
  let!(:base_url) { "https://auth.fuju.example" }
  let!(:client_id) { "bank-client" }
  let!(:client_secret) { "s3cret" }
  let!(:endpoint_url) { "#{base_url}/v1/users/search" }
  let!(:expected_basic_auth) do
    "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
  end

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
    context "200 + users 配列の場合" do
      let!(:payload) do
        {
          "users" => [
            { "id" => "01HALICE000000000000000000", "public_id" => "alice", "icon_url" => "https://cdn.example/alice.webp" },
            { "id" => "01HALICIA00000000000000000", "public_id" => "alicia", "icon_url" => nil },
          ],
        }
      end

      before do
        stub_request(:get, endpoint_url)
          .with(query: { q: "ali", limit: "10" })
          .to_return(
            status: 200,
            body: payload.to_json,
            headers: { "Content-Type" => "application/json" },
          )
      end

      it "users 配列をそのまま返す" do
        result = described_class.call(query: "ali", limit: 10)

        expect(result).to eq(payload["users"])
      end

      it "icon_url が null の要素も保持する" do
        result = described_class.call(query: "ali", limit: 10)

        expect(result.last["icon_url"]).to be_nil
      end

      it "Basic 認証 / GET / q & limit クエリで呼び出す" do
        described_class.call(query: "ali", limit: 10)

        expect(WebMock).to have_requested(:get, endpoint_url)
          .with(
            query: { q: "ali", limit: "10" },
            headers: { "Authorization" => expected_basic_auth },
          )
      end
    end

    context "200 + users が空配列の場合" do
      before do
        stub_request(:get, endpoint_url)
          .with(query: hash_including({ q: "zzz" }))
          .to_return(
            status: 200,
            body: { "users" => [] }.to_json,
            headers: { "Content-Type" => "application/json" },
          )
      end

      it "空配列を返す" do
        expect(described_class.call(query: "zzz", limit: 10)).to eq([])
      end
    end

    context "200 + users キー欠落の場合" do
      before do
        stub_request(:get, endpoint_url).with(query: hash_including({})).to_return(
          status: 200,
          body: {}.to_json,
          headers: { "Content-Type" => "application/json" },
        )
      end

      it "空配列として扱う" do
        expect(described_class.call(query: "ali", limit: 10)).to eq([])
      end
    end

    context "200 + users が配列でない場合（仕様違反レスポンス）" do
      before do
        stub_request(:get, endpoint_url).with(query: hash_including({})).to_return(
          status: 200,
          body: { "users" => "not-an-array" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
      end

      it "空配列として扱う" do
        expect(described_class.call(query: "ali", limit: 10)).to eq([])
      end
    end

    context "200 + 必須キー欠落要素を含む場合" do
      let!(:payload) do
        {
          "users" => [
            { "id" => "01HALICE000000000000000000", "public_id" => "alice", "icon_url" => nil },
            { "id" => nil, "public_id" => "noid", "icon_url" => nil },
            { "id" => "01HNOPUBLICID000000000000A", "icon_url" => nil },
            "not-a-hash",
          ],
        }
      end

      before do
        stub_request(:get, endpoint_url).with(query: hash_including({})).to_return(
          status: 200,
          body: payload.to_json,
          headers: { "Content-Type" => "application/json" },
        )
      end

      it "id / public_id 欠落要素を弾いて返す" do
        result = described_class.call(query: "ali", limit: 10)

        expect(result.size).to eq(1)
        expect(result.first["public_id"]).to eq("alice")
      end
    end

    context "AuthCore 障害 / 異常レスポンスの場合" do
      let!(:base_stub) { stub_request(:get, endpoint_url).with(query: hash_including({})) }

      [
        ["400 (validation error)", { status: 400, body: "" }],
        ["401 (client 認証失敗)", { status: 401, body: "" }],
        ["500", { status: 500, body: "" }],
      ].each do |label, response|
        it "#{label} で AuthcoreUnavailableError を raise する" do
          base_stub.to_return(**response)

          expect { described_class.call(query: "ali", limit: 10) }.to raise_error(AuthcoreUnavailableError)
        end
      end

      it "タイムアウトで AuthcoreUnavailableError を raise する" do
        base_stub.to_timeout

        expect { described_class.call(query: "ali", limit: 10) }.to raise_error(AuthcoreUnavailableError)
      end

      it "接続失敗で AuthcoreUnavailableError を raise する" do
        base_stub.to_raise(Errno::ECONNREFUSED)

        expect { described_class.call(query: "ali", limit: 10) }.to raise_error(AuthcoreUnavailableError)
      end

      it "JSON が不正な場合は「解釈できません」付きで raise する" do
        base_stub.to_return(
          status: 200,
          body: "not-json",
          headers: { "Content-Type" => "application/json" },
        )

        expect { described_class.call(query: "ali", limit: 10) }
          .to raise_error(AuthcoreUnavailableError, /解釈できません/)
      end
    end
  end
end
