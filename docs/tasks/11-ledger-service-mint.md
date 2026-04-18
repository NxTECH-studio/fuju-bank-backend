# 11: Ledger::Mint サービス

> 依存: #06, #07, #08, #09, #10

## 概要

ふじゅ〜の発行（mint）を処理する Service Object を実装する。
`Artifact` → `User` への N ふじゅ〜発行を、複式簿記（system_issuance -N / user +N）として記帳し、
同一トランザクションで残高キャッシュを更新する。

## 背景・目的

- コントローラの肥大化を避けるため、ビジネスロジックを Service Object に集約。
- `Idempotency-Key` 重複時の挙動（既存 transaction を返す）をサービス側で担保。
- `LedgerTransaction` / `LedgerEntry` モデルの整備もこのタスクに含める（#12 と共有）。

## 影響範囲

- **変更対象**:
  - `app/models/ledger_transaction.rb`（新規）
  - `app/models/ledger_entry.rb`（新規）
  - `app/services/ledger/mint.rb`（新規）
  - `spec/models/ledger_transaction_spec.rb`
  - `spec/models/ledger_entry_spec.rb`
  - `spec/services/ledger/mint_spec.rb`
  - `spec/factories/ledger_transactions.rb`
  - `spec/factories/ledger_entries.rb`
- **破壊的変更**: なし
- **外部層への影響**: なし（API は #16 で公開）

## スキーマ変更

なし（#07, #08 で定義済み）

## 実装ステップ

### 1. `LedgerTransaction` / `LedgerEntry` モデル

```ruby
# app/models/ledger_transaction.rb
# 記帳のヘッダ。複式簿記の仕訳を束ねる。
class LedgerTransaction < ApplicationRecord
  KINDS = %w[mint transfer].freeze

  belongs_to :artifact, optional: true
  has_many :entries, class_name: "LedgerEntry", dependent: :restrict_with_exception, inverse_of: :ledger_transaction

  validates :kind, inclusion: { in: KINDS, }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :occurred_at, presence: true
  validates :artifact_id, presence: true, if: :mint_kind?
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
    errors.add(:entries, "must have at least 2 entries") if entries.size < 2
  end
end

# app/models/ledger_entry.rb
# 記帳明細。amount は借方=正、貸方=負。
class LedgerEntry < ApplicationRecord
  belongs_to :ledger_transaction, inverse_of: :entries
  belongs_to :account

  validates :amount, numericality: { only_integer: true, other_than: 0, }
end
```

### 2. `Ledger::Mint` サービス

```ruby
# app/services/ledger/mint.rb
# ふじゅ〜の発行。system_issuance 口座から User 口座へ amount だけ移動する。
class Ledger::Mint
  # @param artifact [Artifact]
  # @param user [User]
  # @param amount [Integer] 正の整数
  # @param idempotency_key [String]
  # @param metadata [Hash] 滞留秒数などの文脈
  # @param occurred_at [Time]
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(artifact:, user:, amount:, idempotency_key:, metadata: {}, occurred_at: Time.current)
    @artifact = artifact
    @user = user
    @amount = amount
    @idempotency_key = idempotency_key
    @metadata = metadata
    @occurred_at = occurred_at
  end

  def call
    raise BankError.new(code: "VALIDATION_FAILED", message: "amount must be positive integer") unless positive_integer?(@amount)

    existing = LedgerTransaction.find_by(idempotency_key: @idempotency_key)
    return existing if existing

    ActiveRecord::Base.transaction do
      tx = LedgerTransaction.new(
        kind: "mint",
        idempotency_key: @idempotency_key,
        artifact_id: @artifact.id,
        metadata: @metadata,
        occurred_at: @occurred_at,
      )
      tx.entries.build(account: Account.system_issuance!, amount: -@amount)
      tx.entries.build(account: @user.account, amount: @amount)
      tx.save!

      Account.system_issuance!.lock!.tap do |acc|
        acc.update!(balance_fuju: acc.balance_fuju - @amount)
      end
      @user.account.lock!.tap do |acc|
        acc.update!(balance_fuju: acc.balance_fuju + @amount)
      end

      tx
    end
  rescue ActiveRecord::RecordNotUnique
    # idempotency_key の競合は再検索で吸収
    LedgerTransaction.find_by!(idempotency_key: @idempotency_key)
  end

  private

  def positive_integer?(value)
    value.is_a?(Integer) && value > 0
  end
end
```

### 3. FactoryBot

```ruby
# spec/factories/ledger_transactions.rb
FactoryBot.define do
  factory :ledger_transaction do
    kind { "mint" }
    sequence(:idempotency_key) { |n| "key-#{n}" }
    artifact
    occurred_at { Time.current }
    metadata { {} }
  end
end

# spec/factories/ledger_entries.rb
FactoryBot.define do
  factory :ledger_entry do
    ledger_transaction
    account
    amount { 1 }
  end
end
```

## テスト要件

- `spec/services/ledger/mint_spec.rb`
  - 正常系: mint すると `user.account.balance_fuju` が N 増える
  - 正常系: `system_issuance` 残高が N 減る（負の値 OK）
  - 正常系: `LedgerTransaction` が 1 件作成され、`entries.count == 2`、`entries.sum(:amount) == 0`
  - 冪等性: 同一 `idempotency_key` を 2 回呼ぶと作成は 1 回だけ、返り値は既存トランザクション
  - 異常系: `amount = 0` / 負値 / 非整数 → `BankError(VALIDATION_FAILED)`
  - 異常系: 同時実行で `ActiveRecord::RecordNotUnique` が飛んだ場合に既存を返す（`allow` + mock で擬似）
- `spec/models/ledger_transaction_spec.rb`
  - entries の SUM != 0 で invalid
  - entries が 1 件以下で invalid
  - idempotency_key 重複で invalid
- N+1: `bullet` が警告を出さない（balance 更新時 lock! で 2 回発行されるのは OK）

## 技術的な補足

- `lock!` によって行ロックを取り、残高更新の race condition を防ぐ。
- `ActiveRecord::RecordNotUnique` は DB 側の unique 制約（#07）で検知され、rescue で既存を返す二重防衛。
- `Ledger` はコンパクトモジュール形式（`class Ledger::Mint`）で書く（RuboCop `Style/ClassAndModuleChildren: compact`）。
- `positive_integer?` は `is_` 接頭辞禁止ルール（`Naming/PredicatePrefix`）に従い `?` メソッドとして定義。
- `metadata` は任意 Hash。MVP ではスキーマ検証しない。

## 非スコープ

- コントローラ（`POST /ledger/mint`） → #16
- broadcast → #20

## 受け入れ基準

- [ ] `Ledger::Mint.call(...)` が動作する
- [ ] 冪等性が担保されている
- [ ] RSpec / RuboCop が通る
- [ ] `bullet` が N+1 警告を出さない
