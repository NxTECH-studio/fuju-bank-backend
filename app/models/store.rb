# Store は QR 決済で受け取り口座となる店舗を表す。
# signing_secret は店舗個別の HMAC 秘密鍵で、QR 署名検証に用いる。
class Store < ApplicationRecord
  # inspect / ログ出力時に平文で漏れるのを防ぐ（filter_parameters は params 用で inspect には効かない）
  self.filter_attributes += [:signing_secret]

  has_one :account, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :signing_secret, presence: true

  scope :active, -> { where(active: true) }
end
