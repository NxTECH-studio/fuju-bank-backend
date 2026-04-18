class ValidationFailedError < BankError
  def initialize(message:)
    super(code: "VALIDATION_FAILED", message: message, http_status: :bad_request)
  end
end
