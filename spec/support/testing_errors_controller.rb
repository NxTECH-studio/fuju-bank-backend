class TestingErrorsController < ApplicationController
  def success
    render(json: { ok: true }, status: :ok)
  end

  def not_found
    raise ActiveRecord::RecordNotFound.new("record missing")
  end

  def record_invalid
    record = TestingErrorsController::DummyRecord.new
    record.errors.add(:base, "is invalid")
    raise ActiveRecord::RecordInvalid.new(record)
  end

  def record_invalid_multiple
    record = TestingErrorsController::DummyRecord.new
    record.errors.add(:name, "is too short")
    record.errors.add(:name, "can't be blank")
    raise ActiveRecord::RecordInvalid.new(record)
  end

  def insufficient_balance
    raise InsufficientBalanceError
  end

  def insufficient_balance_custom_message
    raise InsufficientBalanceError.new(message: "balance: 0 JFY")
  end

  def bank_error_custom_status
    raise BankError.new(code: "TEAPOT", message: "short and stout", http_status: 418)
  end

  def boom
    raise StandardError.new("boom")
  end

  # ActiveRecord::RecordInvalid.new はモデルインスタンスを要求するため、errors だけ持つダミーを使う。
  class DummyRecord
    include ActiveModel::Model
  end
end
