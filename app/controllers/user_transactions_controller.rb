# User 口座の取引履歴（mint 受信 / transfer 送受信）を時系列で返す。
# TODO: 認証は将来拡張
class UserTransactionsController < ApplicationController
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 200

  def index
    user = User.find(params[:user_id])
    account_id = user.account.id
    entries = LedgerEntry
      .where(account_id: account_id)
      .preload(ledger_transaction: { entries: { account: :user } })
      .order(id: :desc)
      .limit(resolved_limit)

    render(json: { data: entries.map { |e| serialize(e, account_id) } })
  end

  private

  def resolved_limit
    raw = params[:limit]
    return DEFAULT_LIMIT if raw.blank?

    value = raw.to_i
    return DEFAULT_LIMIT if value < 1

    [value, MAX_LIMIT].min
  end

  def serialize(entry, account_id)
    tx = entry.ledger_transaction
    counterparty = counterparty_user(tx, account_id)
    {
      entry_id: entry.id,
      transaction_id: tx.id.to_s,
      transaction_kind: tx.kind,
      direction: entry.amount > 0 ? "credit" : "debit",
      amount: entry.amount.abs,
      artifact_id: tx.artifact_id,
      counterparty_user_id: counterparty&.id&.to_s,
      counterparty_public_id: counterparty&.public_id,
      memo: tx.memo,
      metadata: tx.metadata,
      occurred_at: tx.occurred_at.iso8601,
      created_at: tx.created_at.iso8601,
    }
  end

  def counterparty_user(transaction, account_id)
    return nil unless transaction.transfer_kind?

    other_entry = transaction.entries.find { |e| e.account_id != account_id }
    other_entry&.account&.user
  end
end
