# 09: Artist モデル + Account 自動生成（bootstrap）

> 依存: #04, #06

## 概要

`Artist` モデルと `Account` モデルを作成し、`Artist` 作成時に `Account(kind: "artist")` を
1 件自動作成する `after_create` を実装する。

## 背景・目的

- `Artist` と `Account` は 1:1。アプリ層で常にペアで存在することを保証したい。
- `system_issuance` 口座は seed で作られるため、ここでは `Artist` 起点の口座のみ扱う。

## 影響範囲

- **変更対象**:
  - `app/models/artist.rb`（新規）
  - `app/models/account.rb`（新規）
  - `spec/models/artist_spec.rb`（新規）
  - `spec/models/account_spec.rb`（新規）
  - `spec/factories/artists.rb`（新規）
  - `spec/factories/accounts.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: なし

## スキーマ変更

なし（#04, #06 で定義済み）

## 実装ステップ

1. `app/models/artist.rb` を作成
   ```ruby
   # Artist はふじゅ〜の受け取り手を表す。
   # 作成時に対応する Account(kind: "artist") を 1 件生成する。
   class Artist < ApplicationRecord
     has_one :account, dependent: :restrict_with_exception
     has_many :artifacts, dependent: :restrict_with_exception

     validates :name, presence: true

     after_create :bootstrap_account!

     private

     def bootstrap_account!
       create_account!(kind: "artist", balance_fuju: 0)
     end
   end
   ```
2. `app/models/account.rb` を作成
   ```ruby
   # Account は複式簿記の勘定口座。
   # kind = "system_issuance" はふじゅ〜発行源（artist_id = nil）、
   # kind = "artist" は Artist 口座（artist_id 必須、残高 >= 0）。
   class Account < ApplicationRecord
     KINDS = %w[system_issuance artist].freeze

     belongs_to :artist, optional: true
     has_many :ledger_entries, dependent: :restrict_with_exception

     validates :kind, inclusion: { in: KINDS, }
     validates :artist_id, presence: true, if: :artist_kind?
     validates :artist_id, absence: true, if: :system_issuance_kind?
     validates :balance_fuju, numericality: { greater_than_or_equal_to: 0, }, if: :artist_kind?

     scope :system_issuance, -> { where(kind: "system_issuance") }

     def self.system_issuance!
       find_by!(kind: "system_issuance")
     end

     def artist_kind?
       kind == "artist"
     end

     def system_issuance_kind?
       kind == "system_issuance"
     end
   end
   ```
3. FactoryBot
   ```ruby
   # spec/factories/artists.rb
   FactoryBot.define do
     factory :artist do
       sequence(:name) { |n| "Artist #{n}" }
     end
   end

   # spec/factories/accounts.rb
   FactoryBot.define do
     factory :account do
       kind { "artist" }
       artist
       balance_fuju { 0 }

       trait :system_issuance do
         kind { "system_issuance" }
         artist { nil }
       end
     end
   end
   ```
4. モデル spec
   - Artist 作成で Account が 1 件生まれる
   - Artist destroy は関連 Account があれば例外（`restrict_with_exception`）
   - Account の kind=artist で `artist_id` 必須
   - Account の kind=system_issuance で `artist_id` 禁止
   - Artist 口座で `balance_fuju < 0` は validation エラー（DB CHECK を踏む前にモデルで弾く）
5. RSpec / RuboCop を通す

## テスト要件

- `spec/models/artist_spec.rb`
  - `create(:artist)` 後に `artist.account` が存在する
  - `artist.account.kind == "artist"`
  - `artist.account.balance_fuju == 0`
- `spec/models/account_spec.rb`
  - `build(:account, :system_issuance, artist: artist)` は invalid
  - `build(:account, kind: "artist", artist: nil)` は invalid
  - Artist 口座の balance_fuju にマイナス値を代入して save すると invalid
  - `Account.system_issuance!` が seed された口座を返す（spec では before で作る）

## 技術的な補足

- `dependent: :restrict_with_exception` により、ledger_entries がある口座の削除を防ぐ（安全側）。
- FactoryBot の `:system_issuance` trait は `artist { nil }` を明示する必要あり（default で artist が associate されるため）。
- `Account.system_issuance!` はサービス層（#11）で使う。
- Artist 作成後の Account bootstrap は `after_create` で同一トランザクション内に入るため、途中で失敗すると Artist ごとロールバックされる。

## 非スコープ

- `LedgerTransaction` / `LedgerEntry` モデル → #11 / #12 の中で整備
- `Artifact` モデル → #10

## 受け入れ基準

- [ ] `Artist` / `Account` モデルと spec が揃っている
- [ ] Artist 作成で Account が自動生成される
- [ ] kind / artist_id の関係性 validation が効いている
- [ ] RSpec / RuboCop が通る
