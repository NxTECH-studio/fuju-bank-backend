class TestingAuthenticationController < ApplicationController
  def whoami
    render(json: { external_user_id: current_external_user_id }, status: :ok)
  end

  def me
    render(json: { id: current_user.id, external_user_id: current_user.external_user_id }, status: :ok)
  end
end
