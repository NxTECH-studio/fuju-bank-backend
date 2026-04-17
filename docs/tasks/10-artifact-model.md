# 10: Artifact モデル

> 依存: #05, #09

## 概要

`Artifact` モデルを作成する。`location_kind` enum と関連する conditional validation を持つ。

## 背景・目的

- 発行（mint）の起点。マイニング層が「どの Artifact に滞留したか」を指定する。
- MVP は最小限の属性（`title`, `location_kind`, `location_url`）。

## 影響範囲

- **変更対象**:
  - `app/models/artifact.rb`（新規）
  - `spec/models/artifact_spec.rb`（新規）
  - `spec/factories/artifacts.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: なし

## スキーマ変更

なし（#05 で定義済み）

## 実装ステップ

1. `app/models/artifact.rb`
   ```ruby
   # Artifact はふじゅ〜発行の起点となる作品。
   # 物理展示（location_kind = "physical"）と URL（location_kind = "url"）を扱う。
   class Artifact < ApplicationRecord
     LOCATION_KINDS = %w[physical url].freeze

     belongs_to :artist
     has_many :ledger_transactions, dependent: :restrict_with_exception

     validates :title, presence: true
     validates :location_kind, inclusion: { in: LOCATION_KINDS, }
     validates :location_url, presence: true, if: :url_location?
     validates :location_url, absence: true, if: :physical_location?

     def url_location?
       location_kind == "url"
     end

     def physical_location?
       location_kind == "physical"
     end
   end
   ```
2. FactoryBot
   ```ruby
   # spec/factories/artifacts.rb
   FactoryBot.define do
     factory :artifact do
       artist
       sequence(:title) { |n| "Artifact #{n}" }
       location_kind { "physical" }
       location_url { nil }

       trait :url do
         location_kind { "url" }
         location_url { "https://example.com/art/1" }
       end
     end
   end
   ```
3. モデル spec
   - `build(:artifact)` が valid（physical）
   - `build(:artifact, :url)` が valid
   - `build(:artifact, location_kind: "url", location_url: nil)` が invalid
   - `build(:artifact, location_kind: "physical", location_url: "https://...")` が invalid
   - `build(:artifact, location_kind: "magical")` が invalid
4. RSpec / RuboCop を通す

## テスト要件

- 上記 validation パターンの正常系・異常系
- `artist` との関連が機能する（`artifact.artist == artist`）
- `LedgerTransaction` が未実装のため `has_many :ledger_transactions` のテストは #11 で

## 技術的な補足

- `location_url` は URL 形式 validation（`URI` parse）を **入れない**。MVP では「空でなければ OK」。将来のタスクで規約を固めたら strict に。
- `belongs_to :artist` は Rails 5 以降 default required なので明示不要。
- `LedgerTransaction` モデルはこの時点で未定義のため、`has_many :ledger_transactions` は文字列として解決されることを想定。未実装でも Rails は起動する。

## 非スコープ

- Artifact CRUD API → #15

## 受け入れ基準

- [ ] `Artifact` モデル + validation + spec が揃う
- [ ] RSpec / RuboCop が通る
