# 記帳のヘッダ。複式簿記の仕訳を束ねる。
# kind=mint は Artifact → User の発行、kind=transfer は User → User の送金。
class LedgerTransaction < ApplicationRecord
  KINDS = %w[mint transfer].freeze
  MINIMUM_ENTRIES = 2

  belongs_to :artifact, optional: true
  has_many :entries,
           class_name: "LedgerEntry",
           dependent: :restrict_with_exception,
           inverse_of: :ledger_transaction

  validates :kind, inclusion: { in: KINDS }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :occurred_at, presence: true
  validates :artifact_id, presence: true, if: :mint_kind?
  validates :artifact_id, absence: true, if: :transfer_kind?
  validate :entries_sum_must_be_zero
  validate :must_have_at_least_two_entries

  def mint_kind?
    kind == "mint"
  end

  def transfer_kind?
    kind == "transfer"
  end

  private

  def entries_sum_must_be_zero
    return if entries.empty?

    sum = entries.sum { |e| e.amount.to_i }
    errors.add(:entries, "sum must be zero (got #{sum})") if sum != 0
  end

  def must_have_at_least_two_entries
    errors.add(:entries, "must have at least #{MINIMUM_ENTRIES} entries") if entries.size < MINIMUM_ENTRIES
  end
end
