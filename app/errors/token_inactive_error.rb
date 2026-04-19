class TokenInactiveError < BankError
  def initialize(message: "トークンが無効化されています")
    super(code: "TOKEN_INACTIVE", message: message, http_status: :unauthorized)
  end
end
