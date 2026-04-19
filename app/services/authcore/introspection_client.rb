# AuthCore の /v1/auth/introspect を呼び出すクライアント。
# 成功時: IntrospectionResult を返す
# active=false: TokenInactiveError を raise（フェイルクローズ）
# HTTP / ネットワーク失敗: AuthcoreUnavailableError を raise
class Authcore::IntrospectionClient
  ENDPOINT_PATH = "/v1/auth/introspect".freeze
  TIMEOUT_SECONDS = 3

  def self.call(token:)
    new(token: token).call
  end

  def initialize(token:)
    @token = token
  end

  def call
    response = post_introspect
    raise AuthcoreUnavailableError unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    result = Authcore::IntrospectionResult.new(payload)
    raise TokenInactiveError unless result.active?

    result
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
    raise AuthcoreUnavailableError
  rescue JSON::ParserError
    raise AuthcoreUnavailableError.new(message: "AuthCore のレスポンスを解釈できません")
  end

  private

  def post_introspect
    uri = URI.join(Authcore.base_url, ENDPOINT_PATH)
    req = Net::HTTP::Post.new(uri)
    req.basic_auth(Authcore.client_id, Authcore.client_secret)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.body = URI.encode_www_form(token: @token, token_type_hint: "access_token")

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
