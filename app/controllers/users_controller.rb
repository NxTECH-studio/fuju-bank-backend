# /users/me 系エンドポイントと、送金先 lookup（GET /users/lookup）を提供する。
# external_user_id は JWT の sub から取得し、クライアント params からは受け取らない。
#
# `lookup` のみ AuthCore の introspection で active=true を要求する
# （public_id 総当たりによる enumeration 抑止のため）。それ以外の参照系
# （show / show_me / upsert_me）はローカル JWT 検証のみで通す既存挙動を維持する。
class UsersController < ApplicationController
  include IntrospectionRequired

  skip_before_action :verify_introspection!, except: %i[lookup]
  before_action :require_current_user!, only: %i[show show_me]

  def show
    raise AuthorizationError.new(message: "他のユーザー情報は参照できません") if params[:id].to_s != current_user.id.to_s

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
      public_id: upsert_params[:public_id],
    )
    status = user.previously_new_record? ? :created : :ok
    render(json: serialize_user(user), status: status)
  end

  # 送金 UI が `表示名 / public_id → bank 内部 user id` を解決するための公開 API。
  # public_id は AuthCore 側で一意保証されているため、結果は 0 or 1 件に収束する。
  def lookup
    public_id = lookup_params[:public_id]
    validate_public_id!(public_id)

    user = User.find_by(public_id: public_id)
    raise ActiveRecord::RecordNotFound.new("ユーザーが見つかりません") if user.nil?

    render(json: serialize_lookup(user))
  end

  private

  def require_current_user!
    raise AuthenticationError unless current_user
  end

  def upsert_params
    params.permit(:name, :public_key, :public_id)
  end

  def lookup_params
    params.permit(:public_id)
  end

  def validate_public_id!(public_id)
    raise ValidationFailedError.new(message: "public_id is required") if public_id.blank?
    raise ValidationFailedError.new(message: "public_id is invalid") unless User::PUBLIC_ID_REGEX.match?(public_id)
  end

  def serialize_user(user)
    {
      id: user.id,
      name: user.name,
      public_id: user.public_id,
      public_key: user.public_key,
      balance_fuju: user.account.balance_fuju,
      created_at: user.created_at.iso8601,
    }
  end

  # email / balance_fuju / public_key / created_at はプライバシー観点で返さない。
  # icon_url は AuthCore からの取得経路ができるまで常に null。
  def serialize_lookup(user)
    {
      id: user.id,
      public_id: user.public_id,
      name: user.name,
      icon_url: nil,
    }
  end
end
