# ErrorResponder の request spec 専用ダミーコントローラ。
# 本番ルートには載せず、spec 内で Rails.application.routes.draw 経由で一時的にマウントする。
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

  # ActiveRecord::RecordInvalid はモデルインスタンスを要求するため、
  # errors だけを差し替え可能なダミーレコードを用意する。
  class DummyRecord
    include ActiveModel::Model
    include ActiveModel::Validations
  end
end
