class MfaRequiredError < BankError
  def initialize(message: "この操作には MFA 検証が必要です")
    super(code: "MFA_REQUIRED", message: message, http_status: :forbidden)
  end
end
