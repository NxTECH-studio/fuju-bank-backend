# /users/me 系エンドポイントを提供する。
# external_user_id は JWT の sub から取得し、クライアント params からは受け取らない。
class UsersController < ApplicationController
  def show
    raise AuthenticationError unless current_user
    raise BankError.new(code: "FORBIDDEN", message: "他のユーザー情報は参照できません", http_status: :forbidden) if params[:id].to_i != current_user.id

    render(json: serialize_user(current_user))
  end

  def show_me
    raise AuthenticationError unless current_user

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
