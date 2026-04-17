# 残高不足時にサービス層から raise される銀行ドメイン例外。
class InsufficientBalanceError < BankError
  def initialize(message: "残高が不足しています")
    super(code: "INSUFFICIENT_BALANCE", message: message, http_status: 422)
  end
end
