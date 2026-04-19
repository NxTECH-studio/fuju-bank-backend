class TestingAuthenticationController < ApplicationController
  def whoami
    render(json: { external_user_id: current_external_user_id }, status: :ok)
  end
end
