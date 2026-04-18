# 入力バリデーション失敗を表す共通エラー（HTTP 400, code: VALIDATION_FAILED）。
class ValidationFailedError < BankError
  def initialize(message:)
    super(code: "VALIDATION_FAILED", message: message, http_status: :bad_request)
  end
end
