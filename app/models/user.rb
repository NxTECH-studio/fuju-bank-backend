# User はふじゅ〜の受け取り手を表す。
# 作成時に対応する Account(kind: "user") を 1 件生成する。
class User < ApplicationRecord
  ULID_REGEX = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

  # AuthCore の public_id 仕様準拠（英数字 + `_`/`-`、3〜32 文字）。
  # 送金 UI から `GET /users/lookup?public_id=xxx` で逆引きするためのキーで、
  # AuthCore 側で一意保証されている前提を bank 側でも DB unique 制約と
  # モデルバリデーションの両方で守る。
  PUBLIC_ID_REGEX = /\A[a-zA-Z0-9_-]{3,32}\z/

  has_one :account, dependent: :restrict_with_exception
  has_many :artifacts, dependent: :restrict_with_exception

  validates :external_user_id, presence: true,
                               uniqueness: true,
                               format: { with: ULID_REGEX }
  validates :public_id, uniqueness: { allow_nil: true },
                        format: { with: PUBLIC_ID_REGEX, allow_nil: true }

  after_create :bootstrap_account!

  private

  def bootstrap_account!
    create_account!(kind: "user", balance_fuju: 0)
  end
end
