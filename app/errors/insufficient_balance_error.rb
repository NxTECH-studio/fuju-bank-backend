class InsufficientBalanceError < BankError
  def initialize(message: "残高が不足しています")
    super(code: "INSUFFICIENT_BALANCE", message: message)
  end
end
