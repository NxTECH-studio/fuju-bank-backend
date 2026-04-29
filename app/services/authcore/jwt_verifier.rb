# AuthCore JWT を RS256 でローカル検証し、claims を返す PORO。
# Controller の `JwtAuthenticatable` と Cable の `ApplicationCable::Connection` の
# 双方から呼ばれる。introspection は別レイヤ (`IntrospectionRequired`) の責務。
class Authcore::JwtVerifier
  def self.call(token:)
    new(token: token).call
  end

  def initialize(token:)
    @token = token
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

    raise AuthenticationError.new(message: "access token 以外は許可されていません") unless payload["type"] == "access"

    payload
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidAudError, JWT::InvalidIssuerError, JWT::MissingRequiredClaim
    raise AuthenticationError
  end
end
