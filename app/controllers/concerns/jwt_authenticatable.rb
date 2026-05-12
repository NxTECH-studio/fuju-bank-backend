# Bearer JWT を検証し、current_external_user_id / current_jwt_claims を供給する。
# ローカル検証のみ（introspection は別 concern で提供）。
#
# デフォルトでは AuthCore が発行した `type=access` のユーザートークンしか
# 受理しない。Service-to-Service 経路（fuju → /ledger/mint 代理 mint など）が
# 必要なコントローラはクラスレベルで `service_actor_allowed!` を宣言すること。
# その場合 `type=service` も追加で受理し、`current_actor_type` で actor 種別を
# 区別できる（`"access"` / `"service"`）。
module JwtAuthenticatable
  extend ActiveSupport::Concern

  ACCESS_ACTOR  = "access".freeze
  SERVICE_ACTOR = "service".freeze

  included do
    before_action :authenticate!
  end

  class_methods do
    # コントローラが service token も受理することを宣言する。デフォルトは
    # access token のみ。Ledger の mint のように外部サービスからの代理
    # 呼び出しを受ける口だけがこれを使う。
    def service_actor_allowed!
      @service_actor_allowed = true
    end

    def service_actor_allowed?
      @service_actor_allowed == true
    end
  end

  private

  def authenticate!
    token = extract_bearer_token
    @current_jwt_claims = Authcore::JwtVerifier.call(
      token: token,
      allowed_types: allowed_token_types,
    )
    @current_external_user_id = @current_jwt_claims.fetch("sub")
    @current_actor_type = @current_jwt_claims.fetch("type")
  end

  def allowed_token_types
    self.class.service_actor_allowed? ? [ACCESS_ACTOR, SERVICE_ACTOR] : [ACCESS_ACTOR]
  end

  def current_jwt_claims
    @current_jwt_claims
  end

  def current_external_user_id
    @current_external_user_id
  end

  # `"access"` (ユーザー) または `"service"` (Client Credentials) のいずれか。
  def current_actor_type
    @current_actor_type
  end

  def service_actor?
    current_actor_type == SERVICE_ACTOR
  end

  # NOTE: 実運用上は ApplicationController#current_user が override しており、
  # こちらの定義は呼ばれない（lazy provisioning は POST /users/me 限定の方針）。
  # ここでは「service actor は current_user を持たない」というガード意図を
  # 残しておくが、UserProvisioner.call は public_id 必須化以降 nil で呼ぶと
  # presence validation で raise するため、誤って fallback で呼ばれても
  # silent に User を作ることはない。include 順を変えるリファクタを行う場合は
  # ApplicationController 側の find-only セマンティクスを維持すること。
  def current_user
    raise AuthenticationError.new(message: "service actor は current_user を持たない") if service_actor?

    @current_user ||= UserProvisioner.call(external_user_id: current_external_user_id)
  end

  def extract_bearer_token
    header = request.headers["Authorization"]
    return nil if header.blank?

    match = header.match(/\ABearer\s+(.+)\z/)
    match && match[1]
  end
end
