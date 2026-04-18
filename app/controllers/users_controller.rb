# User 作成・参照 API。
# MVP では未認証（管理者が手動で叩く想定）。認証は将来別基盤で拡張する。
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
