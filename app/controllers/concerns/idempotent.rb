# Idempotency-Key ヘッダ（または request body の idempotency_key）を解釈する concern。
# 使用側 controller で idempotency_key! を呼ぶことで、未指定 / 長さ不正時は
# BankError(VALIDATION_FAILED, 400) を raise する。
module Idempotent
  extend ActiveSupport::Concern

  IDEMPOTENCY_HEADER = "Idempotency-Key".freeze
  # 推測困難性の最小担保（UUID 36 文字 / ULID 26 文字より十分小さく安全）と、
  # DB 列の VARCHAR(255) 上限を意識した境界。
  MIN_LENGTH = 8
  MAX_LENGTH = 255

  def idempotency_key!
    key = request.headers[IDEMPOTENCY_HEADER].presence || params[:idempotency_key].presence
    raise ValidationFailedError.new(message: "Idempotency-Key is required") if key.blank?
    raise ValidationFailedError.new(message: "Idempotency-Key length invalid") unless valid_length?(key)

    key
  end

  private

  def valid_length?(key)
    key.length.between?(MIN_LENGTH, MAX_LENGTH)
  end
end
