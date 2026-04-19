# ローカル JWT 検証（JwtAuthenticatable）の後段で AuthCore introspection を呼ぶ。
# 金銭移動系コントローラでのみ include する。
module IntrospectionRequired
  extend ActiveSupport::Concern

  included do
    before_action :verify_introspection!
  end

  private

  def verify_introspection!
    token = extract_bearer_token
    @introspection_result = Authcore::IntrospectionClient.call(token: token)

    raise AuthenticationError if @introspection_result.sub != current_external_user_id
  end

  def introspection_result
    @introspection_result
  end
end
