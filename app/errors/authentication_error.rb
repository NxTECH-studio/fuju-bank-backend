class AuthenticationError < BankError
  def initialize(message: "認証に失敗しました")
    super(code: "UNAUTHENTICATED", message: message, http_status: 401)
  end
end
