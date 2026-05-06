# 認証は成功したが、当該リソース / アクションへの権限が不足する場合に raise する。
# 認証失敗（AuthenticationError, 401）と区別するため 403 を返す。
class AuthorizationError < BankError
  def initialize(message: "権限が不足しています")
    super(code: "FORBIDDEN", message: message, http_status: :forbidden)
  end
end
