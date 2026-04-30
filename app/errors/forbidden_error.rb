class ForbiddenError < BankError
  def initialize(message: "アクセスが許可されていません")
    super(code: "FORBIDDEN", message: message, http_status: :forbidden)
  end
end
