# 記帳明細。amount は借方=正 / 貸方=負。
# 同一 LedgerTransaction 内の entries の SUM(amount) は常に 0。
class LedgerEntry < ApplicationRecord
  belongs_to :ledger_transaction, inverse_of: :entries
  belongs_to :account

  validates :amount, numericality: { only_integer: true, other_than: 0 }
end
