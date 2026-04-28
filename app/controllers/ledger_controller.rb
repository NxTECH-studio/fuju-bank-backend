# 金銭移動系エンドポイント（mint / transfer）。
# ローカル JWT 検証に加えて AuthCore introspection を要求する。
# MFA 要否は MVP 時点では未決定。必要になった時点で `include MfaRequired` を追加する。
#
# `mint` は service-to-service 経路（fuju-emotion-model から creator への
# 代理 mint）も受け付ける。そのために `service_actor_allowed!` を宣言した
# 上で、service token から呼ばれた場合に限り `mint:creator_payouts`
# スコープを要求する。ユーザートークン経由（既存 MVP 経路）は scope 検査
# をスキップする。
#
# 受取人 ID 空間: `mint_params[:user_id]` は **AuthCore の `sub`
# (external_user_id; ULID 26 文字)** を期待する。Bank 内部の autoincrement PK
# (`users.id`) は受け付けない。これにより SNS の作者 ID（= AuthCore sub）と
# Bank の受取口座が cross-service で一意に対応することが保証される。Bank に
# 該当 User が未登録なら UserProvisioner で lazy 作成する。
#
# artifact_id: 任意。fuju-emotion-model 由来の代理 mint は SNS content を
# Bank に Artifact としてミラーしないため、未指定 → ledger_transactions.artifact_id
# は NULL のまま記帳される。content 由来の追跡情報は metadata に入れる運用。
class LedgerController < ApplicationController
  include IntrospectionRequired
  include Idempotent

  service_actor_allowed!

  MINT_SCOPE = "mint:creator_payouts".freeze

  def mint
    enforce_mint_scope_for_service_actor!

    user = resolve_recipient!(mint_params[:user_id])
    artifact = resolve_optional_artifact(mint_params[:artifact_id])

    tx = Ledger::Mint.call(
      artifact: artifact,
      user: user,
      amount: mint_params[:amount].to_i,
      idempotency_key: idempotency_key!,
      metadata: mint_params[:metadata].to_h,
      occurred_at: parse_occurred_at(mint_params[:occurred_at]),
    )

    render(json: serialize_transaction(tx), status: :ok)
  end

  def transfer
    from_user = User.find(transfer_params[:from_user_id])
    to_user = User.find(transfer_params[:to_user_id])

    tx = Ledger::Transfer.call(
      from_user: from_user,
      to_user: to_user,
      amount: transfer_params[:amount].to_i,
      idempotency_key: idempotency_key!,
      memo: transfer_params[:memo],
      metadata: transfer_params[:metadata].to_h,
      occurred_at: parse_occurred_at(transfer_params[:occurred_at]),
    )

    render(json: serialize_transaction(tx), status: :ok)
  end

  private

  # service token から呼ばれた場合のみ `mint:creator_payouts` スコープを
  # 要求する。ユーザートークン経由は MVP 互換のため scope 検査スキップ。
  def enforce_mint_scope_for_service_actor!
    return unless service_actor?
    return if introspection_result.scope?(MINT_SCOPE)

    raise AuthorizationError.new(message: "service token に scope=#{MINT_SCOPE} が必要です")
  end

  # mint の受取人 User を解決する。`user_id` パラメータは
  # **AuthCore の `sub`（external_user_id; ULID 26 文字 Crockford Base32）**
  # を期待する。Bank 内部 PK は受け付けない（cross-service 契約として
  # external_user_id に統一）。Bank 側に該当 User が無ければ
  # UserProvisioner で lazy 作成する（fuju-emotion-model 経由の代理 mint で
  # creator がまだ Bank HUD にログインしていないケースに対応）。
  def resolve_recipient!(external_user_id)
    raise ValidationFailedError.new(message: "user_id is required") if external_user_id.blank?
    raise ValidationFailedError.new(message: "user_id must be a ULID (external_user_id)") unless User::ULID_REGEX.match?(external_user_id)

    UserProvisioner.call(external_user_id: external_user_id)
  end

  # artifact_id は任意。指定された場合は存在チェック、未指定なら nil を返す
  # （ledger_transactions.artifact_id は nullable）。
  def resolve_optional_artifact(artifact_id)
    return nil if artifact_id.blank?

    Artifact.find(artifact_id)
  end

  # `params.expect` は全 leaf フィールドを必須とするため artifact_id を
  # optional にできない。代理 mint 経路で artifact_id を省略可にする
  # 設計のため、明示的に require + permit を使う。
  # rubocop:disable Rails/StrongParametersExpect
  def mint_params
    @mint_params ||= params.require(:ledger).permit(
      :artifact_id, :user_id, :amount, :occurred_at, metadata: {},
    )
  end
  # rubocop:enable Rails/StrongParametersExpect

  def transfer_params
    @transfer_params ||= params.expect(
      ledger: [
        :from_user_id,
        :to_user_id,
        :amount,
        :memo,
        :occurred_at,
        { metadata: {} },
      ],
    )
  end

  def parse_occurred_at(value)
    value.present? ? Time.zone.parse(value) : Time.current
  end

  def serialize_transaction(transaction)
    {
      id: transaction.id,
      kind: transaction.kind,
      artifact_id: transaction.artifact_id,
      idempotency_key: transaction.idempotency_key,
      memo: transaction.memo,
      metadata: transaction.metadata,
      occurred_at: transaction.occurred_at.iso8601,
      created_at: transaction.created_at.iso8601,
    }
  end
end
