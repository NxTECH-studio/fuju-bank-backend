# 記帳イベントを UserChannel へ broadcast するユーティリティ。
# 受け手（amount > 0 の entry）の User にのみ credit ペイロードを送る。
class Ledger::Notifier
  # @param ledger_transaction [LedgerTransaction]
  def self.broadcast_credits(ledger_transaction)
    new(ledger_transaction).broadcast_credits
  end

  def initialize(ledger_transaction)
    @tx = ledger_transaction
  end

  def broadcast_credits
    credit_entries.each do |entry|
      user = entry.account.user
      next if user.nil?

      UserChannel.broadcast_to(user, payload_for(entry))
    end
  end

  private

  def credit_entries
    @tx.entries.select { |e| e.amount > 0 }
  end

  def payload_for(entry)
    {
      type: "credit",
      amount: entry.amount,
      transaction_id: @tx.id,
      transaction_kind: @tx.kind,
      artifact_id: @tx.artifact_id,
      from_user_id: from_user_id,
      metadata: @tx.metadata,
      occurred_at: @tx.occurred_at.iso8601,
    }
  end

  def from_user_id
    return nil unless @tx.transfer_kind?

    debit_entry = @tx.entries.find { |e| e.amount < 0 }
    debit_entry&.account&.user_id
  end
end
