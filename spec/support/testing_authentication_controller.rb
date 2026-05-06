class TestingAuthenticationController < ApplicationController
  def whoami
    render(json: { external_user_id: current_external_user_id }, status: :ok)
  end

  def me
    raise AuthenticationError unless current_user

    render(json: { id: current_user.id, external_user_id: current_user.external_user_id }, status: :ok)
  end
end
