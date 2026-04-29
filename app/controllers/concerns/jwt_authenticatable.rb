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
    @current_jwt_claims = Authcore::JwtVerifier.call(token: token)
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
end
