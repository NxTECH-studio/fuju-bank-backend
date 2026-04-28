# /users/me 系エンドポイントを提供する。
# external_user_id は JWT の sub から取得し、クライアント params からは受け取らない。
class UsersController < ApplicationController
  before_action :require_current_user!, only: %i[show show_me]

  def show
    raise ForbiddenError.new(message: "他のユーザー情報は参照できません") if params[:id].to_i != current_user.id

    render(json: serialize_user(current_user))
  end

  def show_me
    render(json: serialize_user(current_user))
  end

  def upsert_me
    user = UserProvisioner.call(
      external_user_id: current_external_user_id,
      name: upsert_params[:name],
      public_key: upsert_params[:public_key],
    )
    status = user.previously_new_record? ? :created : :ok
    render(json: serialize_user(user), status: status)
  end

  private

  def require_current_user!
    raise AuthenticationError unless current_user
  end

  def upsert_params
    params.permit(:name, :public_key)
  end

  def serialize_user(user)
    {
      id: user.id,
      name: user.name,
      public_key: user.public_key,
      balance_fuju: user.account.balance_fuju,
      created_at: user.created_at.iso8601,
    }
  end
end
