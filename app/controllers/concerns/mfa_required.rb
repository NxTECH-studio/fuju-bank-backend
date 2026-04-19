# MFA 検証済みトークンのみ許可する。IntrospectionRequired の後に include すること。
module MfaRequired
  extend ActiveSupport::Concern

  included do
    before_action :require_mfa_verified!
  end

  private

  def require_mfa_verified!
    raise MfaRequiredError unless introspection_result&.mfa_verified?
  end
end
