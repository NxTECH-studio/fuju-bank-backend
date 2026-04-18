# Idempotent concern の挙動を request spec から検証するためのテスト専用 controller。
class TestingIdempotentController < ApplicationController
  include Idempotent

  def show
    render(json: { idempotency_key: idempotency_key! }, status: :ok)
  end
end
