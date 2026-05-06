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
  # mint は Artifact 紐付けが推奨だが必須ではない:
  # fuju-emotion-model 由来の代理 mint は SNS 側 content を Artifact として
  # ミラーしないため artifact_id=nil で記帳される（content_id は metadata 側に
  # 入れて補完する運用）。transfer は今まで通り Artifact 紐付け禁止。
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
