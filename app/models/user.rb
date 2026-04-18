# User はふじゅ〜の受け取り手を表す。
# 作成時に対応する Account(kind: "user") を 1 件生成する。
class User < ApplicationRecord
  has_one :account, dependent: :restrict_with_exception
  has_many :artifacts, dependent: :restrict_with_exception

  validates :name, presence: true

  after_create :bootstrap_account!

  private

  def bootstrap_account!
    create_account!(kind: "user", balance_fuju: 0)
  end
end
