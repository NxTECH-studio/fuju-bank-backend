module ErrorResponder
  extend ActiveSupport::Concern

  # rescue_from は LIFO で評価される（後勝ち）。より汎用的な StandardError を先に登録し、
  # 具体的な例外クラスをあとに登録することで、具体的な handler が優先されるようにする。
  included do
    rescue_from StandardError, with: :render_internal_error unless Rails.env.development?
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_validation_failed
    rescue_from BankError, with: :render_bank_error
  end

  private

  def render_error(code:, message:, status:)
    render(
      json: { error: { code: code, message: message } },
      status: status,
    )
  end

  def render_not_found(exception)
    render_error(code: "NOT_FOUND", message: exception.message, status: :not_found)
  end

  def render_validation_failed(exception)
    render_error(code: "VALIDATION_FAILED", message: exception.record.errors.full_messages.join(", "), status: :unprocessable_entity)
  end

  def render_bank_error(exception)
    render_error(code: exception.code, message: exception.message, status: exception.http_status)
  end

  def render_internal_error(exception)
    Rails.logger.error(exception.full_message)
    render_error(code: "INTERNAL_ERROR", message: "内部エラーが発生しました", status: :internal_server_error)
  end
end
