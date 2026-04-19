# 金銭移動系エンドポイント（mint / transfer）。
# ローカル JWT 検証に加えて AuthCore introspection を要求する。
# MFA 要否は MVP 時点では未決定。必要になった時点で `include MfaRequired` を追加する。
class LedgerController < ApplicationController
  include IntrospectionRequired
  include Idempotent

  def mint
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
