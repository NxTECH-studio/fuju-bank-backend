# AuthCore JWT を RS256 でローカル検証し、claims を返す PORO。
# Controller の `JwtAuthenticatable` と Cable の `ApplicationCable::Connection` の
# 双方から呼ばれる。introspection は別レイヤ (`IntrospectionRequired`) の責務。
#
# `allowed_types` は token の `type` claim に許される値の集合。デフォルトは
# `["access"]` で、ユーザートークン経路のみ受理する。Service-to-Service 経路
# (e.g. fuju → /ledger/mint の代理 mint) はコントローラ側で
# `["access", "service"]` を渡し、JwtAuthenticatable が
# `service_actor_allowed?` を見て切り替える。
class Authcore::JwtVerifier
  DEFAULT_ALLOWED_TYPES = ["access"].freeze

  def self.call(token:, allowed_types: DEFAULT_ALLOWED_TYPES)
    new(token: token, allowed_types: allowed_types).call
  end

  def initialize(token:, allowed_types: DEFAULT_ALLOWED_TYPES)
    @token = token
    @allowed_types = allowed_types
  end

  def call
    raise AuthenticationError if @token.blank?

    payload, _header = JWT.decode(
      @token,
      Authcore.jwt_public_key,
      true,
      {
        algorithm: "RS256",
        verify_aud: true,
        aud: Authcore.expected_audience,
        verify_iss: true,
        iss: Authcore.expected_issuer,
        verify_expiration: true,
        required_claims: ["sub"],
      },
    )

    raise AuthenticationError.new(message: "このエンドポイントでは type=#{payload['type']} は許可されていません") unless @allowed_types.include?(payload["type"])

    payload
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidAudError, JWT::InvalidIssuerError, JWT::MissingRequiredClaim
    raise AuthenticationError
  end
end
