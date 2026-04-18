# Artifact はふじゅ〜発行の起点となる作品。
# 物理展示（location_kind = "physical"）と URL（location_kind = "url"）を扱う。
class Artifact < ApplicationRecord
  LOCATION_KINDS = %w[physical url].freeze

  belongs_to :user
  has_many :ledger_transactions, dependent: :restrict_with_exception

  validates :title, presence: true
  validates :location_kind, inclusion: { in: LOCATION_KINDS }
  validates :location_url, presence: true, if: :url_location?
  validates :location_url, absence: true, if: :physical_location?

  def url_location?
    location_kind == "url"
  end

  def physical_location?
    location_kind == "physical"
  end
end
