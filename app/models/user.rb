# User はふじゅ〜の受け取り手を表す。
# 作成時に対応する Account(kind: "user") を 1 件生成する。
class User < ApplicationRecord
  ULID_REGEX = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

  has_one :account, dependent: :restrict_with_exception
  has_many :artifacts, dependent: :restrict_with_exception

  validates :external_user_id, presence: true,
                               uniqueness: true,
                               format: { with: ULID_REGEX }

  after_create :bootstrap_account!

  private

  def bootstrap_account!
    create_account!(kind: "user", balance_fuju: 0)
  end
end
