# Account は複式簿記の勘定口座。
# kind = "system_issuance" はふじゅ〜発行源（user_id = nil）、
# kind = "user" は User 口座（user_id 必須、残高 >= 0）、
# kind = "store" は Store 口座（store_id 必須、残高 >= 0）。
class Account < ApplicationRecord
  KINDS = %w[system_issuance user store].freeze

  belongs_to :user, optional: true
  belongs_to :store, optional: true
  has_many :ledger_entries, dependent: :restrict_with_exception

  validates :kind, inclusion: { in: KINDS }
  validates :user_id, presence: true, if: :user_kind?
  validates :user_id, absence: true, unless: :user_kind?
  validates :store_id, presence: true, if: :store_kind?
  validates :store_id, absence: true, unless: :store_kind?
  validates :balance_fuju, numericality: { greater_than_or_equal_to: 0 }, if: :balance_non_negative?

  scope :system_issuance, -> { where(kind: "system_issuance") }

  def self.system_issuance!
    find_by!(kind: "system_issuance")
  end

  def user_kind?
    kind == "user"
  end

  def system_issuance_kind?
    kind == "system_issuance"
  end

  def store_kind?
    kind == "store"
  end

  private

  def balance_non_negative?
    user_kind? || store_kind?
  end
end
