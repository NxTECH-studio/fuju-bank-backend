# TODO: 認証は将来拡張（マイニング層からの署名検証など）
class LedgerController < ApplicationController
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

  def parse_occurred_at(value)
    value.present? ? Time.zone.parse(value) : Time.current
  end

  def serialize_transaction(transaction)
    {
      id: transaction.id,
      kind: transaction.kind,
      artifact_id: transaction.artifact_id,
      idempotency_key: transaction.idempotency_key,
      metadata: transaction.metadata,
      occurred_at: transaction.occurred_at.iso8601,
      created_at: transaction.created_at.iso8601,
    }
  end
end
