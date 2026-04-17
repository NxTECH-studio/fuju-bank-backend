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

  def insufficient_balance
    raise InsufficientBalanceError
  end

  def boom
    raise StandardError.new("boom")
  end

  # ActiveRecord::RecordInvalid.new はモデルインスタンスを要求するため、errors だけ持つダミーを使う。
  class DummyRecord
    include ActiveModel::Model
  end
end
