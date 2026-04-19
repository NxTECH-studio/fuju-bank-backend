class UsersController < ApplicationController
  def show
    user = User.includes(:account).find(params[:id])
    render(json: serialize_user(user))
  end

  def create
    user = User.create!(user_params)
    render(json: serialize_user(user), status: :created)
  end

  private

  def user_params
    params.expect(user: %i[external_user_id name public_key])
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
