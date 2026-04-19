class TestingMfaController < ApplicationController
  include IntrospectionRequired
  include MfaRequired

  def show
    render(json: { ok: true }, status: :ok)
  end
end
