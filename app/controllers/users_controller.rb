class UsersController < ApplicationController
  def create
    user = User.create!(user_params)
    render(json: serialize(user), status: :created)
  end

  private

  def user_params
    params.expect(user: %i[name public_key])
  end

  def serialize(user)
    {
      id: user.id,
      name: user.name,
      public_key: user.public_key,
      balance_fuju: user.account.balance_fuju,
      created_at: user.created_at.iso8601,
    }
  end
end
