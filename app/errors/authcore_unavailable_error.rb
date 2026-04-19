class AuthcoreUnavailableError < BankError
  def initialize(message: "認証基盤に接続できません")
    super(code: "AUTHCORE_UNAVAILABLE", message: message, http_status: :service_unavailable)
  end
end
