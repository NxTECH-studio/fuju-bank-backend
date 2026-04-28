# 金銭移動系エンドポイント（mint / transfer）。
# ローカル JWT 検証に加えて AuthCore introspection を要求する。
# MFA 要否は MVP 時点では未決定。必要になった時点で `include MfaRequired` を追加する。
#
# `mint` は service-to-service 経路（fuju-emotion-model から creator への
# 代理 mint）も受け付ける。そのために `service_actor_allowed!` を宣言した
# 上で、service token から呼ばれた場合に限り `mint:creator_payouts`
# スコープを要求する。ユーザートークン経由（既存 MVP 経路）は scope 検査
# をスキップする。
class LedgerController < ApplicationController
  include IntrospectionRequired
  include Idempotent

  service_actor_allowed!

  MINT_SCOPE = "mint:creator_payouts".freeze

  def mint
    enforce_mint_scope_for_service_actor!

    artifact = Artifact.find(mint_params[:artifact_id])
    user = User.find(mint_params[:user_id])

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

  def mint_params
    @mint_params ||= params.expect(
      ledger: [
        :artifact_id,
        :user_id,
        :amount,
        :occurred_at,
        { metadata: {} },
      ],
    )
  end

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
