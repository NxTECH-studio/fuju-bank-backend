# Bearer JWT を検証し、current_external_user_id / current_jwt_claims を供給する。
# ローカル検証のみ（introspection は別 concern で提供）。
module JwtAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  private

  def authenticate!
    token = extract_bearer_token
    raise AuthenticationError if token.blank?

    @current_jwt_claims = decode_and_verify!(token)
    @current_external_user_id = @current_jwt_claims.fetch("sub")
  end

  def current_jwt_claims
    @current_jwt_claims
  end

  def current_external_user_id
    @current_external_user_id
  end

  def extract_bearer_token
    header = request.headers["Authorization"]
    return nil if header.blank?

    match = header.match(/\ABearer\s+(.+)\z/)
    match && match[1]
  end

  def decode_and_verify!(token)
    payload, _header = JWT.decode(
      token,
      Authcore.jwt_public_key,
      true,
      {
        algorithm: "RS256",
        verify_aud: true,
        aud: Authcore.expected_audience,
        verify_iss: true,
        iss: Authcore.expected_issuer,
        verify_expiration: true,
      },
    )

    raise AuthenticationError.new(message: "access token 以外は許可されていません") unless payload["type"] == "access"

    payload
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidAudError, JWT::InvalidIssuerError
    raise AuthenticationError
  end
end
