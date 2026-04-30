# AuthCore の introspect レスポンスを扱う値オブジェクト。
class Authcore::IntrospectionResult
  attr_reader :active, :sub, :client_id, :username, :token_type,
              :mfa_verified, :aud, :exp, :iat, :scope

  def initialize(payload)
    @active        = payload["active"]
    @sub           = payload["sub"]
    @client_id     = payload["client_id"]
    @username      = payload["username"]
    @token_type    = payload["token_type"]
    @mfa_verified  = payload["mfa_verified"]
    @aud           = payload["aud"]
    @exp           = payload["exp"]
    @iat           = payload["iat"]
    @scope         = payload["scope"].to_s
  end

  def active?
    @active == true
  end

  def mfa_verified?
    @mfa_verified == true
  end

  # scope クレームに `name` が含まれるかを判定する。AuthCore は scope を
  # 半角スペース区切りの文字列で返す（OAuth2 慣習）。
  def scope?(name)
    @scope.split.include?(name)
  end
end
