# /users/me 系エンドポイントと、送金先検索（GET /users/search）を提供する。
# external_user_id は JWT の sub から取得し、クライアント params からは受け取らない。
#
# `search` のみ AuthCore の introspection で active=true を要求する
# （表示名 enumeration 抑止のため）。それ以外の参照系
# （show / show_me / upsert_me）はローカル JWT 検証のみで通す既存挙動を維持する。
class UsersController < ApplicationController
  include IntrospectionRequired

  skip_before_action :verify_introspection!, except: %i[search]
  before_action :require_current_user!, only: %i[show show_me search]

  SEARCH_DEFAULT_LIMIT = 10
  SEARCH_MAX_LIMIT = 20
  SEARCH_QUERY_MIN_LENGTH = 2
  SEARCH_QUERY_MAX_LENGTH = 64

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

  # 送金 UI が「表示名で候補を絞り込む」ための公開 API。
  # users.name を ILIKE 部分一致で検索し、最大 limit 件（デフォルト 10 / 上限 20）を返す。
  # 自分自身は API 側で常に除外する。0 件は 200 + 空配列を返す（404 ではない）。
  def search
    q = search_query_params[:q].to_s.strip
    validate_search_query!(q)
    limit = parse_search_limit(search_query_params[:limit])

    users = User.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(q)}%")
      .where.not(id: current_user.id)
      .order(:id)
      .limit(limit)

    render(json: { users: users.map { |u| serialize_search_hit(u) } })
  end

  private

  def require_current_user!
    raise AuthenticationError unless current_user
  end

  def upsert_params
    params.permit(:name, :public_key, :public_id)
  end

  def search_query_params
    params.permit(:q, :limit)
  end

  def validate_search_query!(query)
    raise ValidationFailedError.new(message: "q is required") if query.blank?
    raise ValidationFailedError.new(message: "q must be at least #{SEARCH_QUERY_MIN_LENGTH} characters") if query.length < SEARCH_QUERY_MIN_LENGTH
    raise ValidationFailedError.new(message: "q must be at most #{SEARCH_QUERY_MAX_LENGTH} characters") if query.length > SEARCH_QUERY_MAX_LENGTH
  end

  # limit は 1..SEARCH_MAX_LIMIT に強制。範囲外指定は 422 を返す。未指定はデフォルト。
  def parse_search_limit(raw)
    return SEARCH_DEFAULT_LIMIT if raw.blank?

    value = Integer(raw, 10)
    raise ValidationFailedError.new(message: "limit must be between 1 and #{SEARCH_MAX_LIMIT}") unless value.between?(1, SEARCH_MAX_LIMIT)

    value
  rescue ArgumentError, TypeError
    raise ValidationFailedError.new(message: "limit must be an integer")
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
  def serialize_search_hit(user)
    {
      id: user.id,
      public_id: user.public_id,
      name: user.name,
      icon_url: nil,
    }
  end
end
