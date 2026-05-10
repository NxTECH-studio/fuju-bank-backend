require "net/http"

# AuthCore の /v1/users/search を呼び出し、public_id 前方一致でヒットしたユーザー配列を返すクライアント。
# 成功時: 各要素 { "id" / "public_id" / "icon_url" } のハッシュ配列
# 4xx / 5xx / ネットワーク失敗 / JSON 不正: いずれも AuthcoreUnavailableError を raise（フェイルクローズ）
class Authcore::UserSearchClient
  ENDPOINT_PATH = "/v1/users/search".freeze
  TIMEOUT_SECONDS = 3

  def self.call(query:, limit:)
    new(query: query, limit: limit).call
  end

  def initialize(query:, limit:)
    @query = query
    @limit = limit
  end

  def call
    response = get_search
    raise AuthcoreUnavailableError unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    Array(payload["users"])
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
    raise AuthcoreUnavailableError
  rescue JSON::ParserError
    raise AuthcoreUnavailableError.new(message: "AuthCore のレスポンスを解釈できません")
  end

  private

  def get_search
    uri = URI.join(Authcore.base_url, ENDPOINT_PATH)
    uri.query = URI.encode_www_form(q: @query, limit: @limit)
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(Authcore.client_id, Authcore.client_secret)

    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT_SECONDS,
      read_timeout: TIMEOUT_SECONDS,
    ) do |http|
      http.request(req)
    end
  end
end
