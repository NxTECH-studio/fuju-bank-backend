class TestingIdempotentController < ApplicationController
  include Idempotent

  def show
    render(json: { idempotency_key: idempotency_key! }, status: :ok)
  end
end
