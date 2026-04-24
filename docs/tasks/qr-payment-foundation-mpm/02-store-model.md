# STEP 02: `Store` モデルを新規作成

- **前提 STEP**: [`01-schema-ridgepole.md`](./01-schema-ridgepole.md)（`stores` テーブルが適用済み）
- **次の STEP**: [`03-account-kind-store.md`](./03-account-kind-store.md)
- **全体像**: [`00-overview.md`](./00-overview.md)

## 目的

店舗の基本情報と `signing_secret` を保持するモデルを用意する。Account との関連は次の STEP で追加する。

## 変更ファイル

- `app/models/store.rb`（新規）
- `spec/models/store_spec.rb`（新規）
- `spec/factories/stores.rb`（新規）

## 作業内容

1. `Store < ApplicationRecord` を作成。クラスコメント必須（RuboCop）
2. `has_one :account, dependent: :restrict_with_exception`
3. `validates :code, presence: true, uniqueness: true`
4. `validates :name, :signing_secret, presence: true`
5. `scope :active, -> { where(active: true) }`
6. FactoryBot で `signing_secret` は `SecureRandom.hex(32)` 生成

## 受け入れ基準

- `Store.create!(code: "...", name: "...", signing_secret: "...")` が成功する
- バリデーションエラーが適切に発火する

## テスト観点

- 正常系 create
- `code` 一意性違反
- 必須項目欠落
