# 12: Ledger::Transfer サービス

> 依存: #06, #07, #08, #09, #11（LedgerTransaction / LedgerEntry モデルを共有）

## 概要

Artist → Artist のふじゅ〜送金を処理する Service Object を実装する。
残高不足時は `InsufficientBalanceError` を raise し、トランザクション全体を rollback する。

## 背景・目的

- PayPay 的な Artist 間送金を MVP で提供。
- 残高不足の検知はモデル validation + DB CHECK 制約の二重防衛。
- 冪等化は `Ledger::Mint` と同じロジック。

## 影響範囲

- **変更対象**:
  - `app/services/ledger/transfer.rb`（新規）
  - `app/errors/insufficient_balance_error.rb`（#01 で追加済みを利用 / 無ければ本 PR で追加）
  - `spec/services/ledger/transfer_spec.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: なし（API は #17 で）

## スキーマ変更

なし

## 実装ステップ

### 1. `Ledger::Transfer` サービス

```ruby
# app/services/ledger/transfer.rb
# Artist → Artist のふじゅ〜送金。
# 残高不足の場合は InsufficientBalanceError を raise し、全体を rollback する。
class Ledger::Transfer
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(from_artist:, to_artist:, amount:, idempotency_key:, memo: nil, metadata: {}, occurred_at: Time.current)
    @from_artist = from_artist
    @to_artist = to_artist
    @amount = amount
    @idempotency_key = idempotency_key
    @memo = memo
    @metadata = metadata
    @occurred_at = occurred_at
  end

  def call
    raise BankError.new(code: "VALIDATION_FAILED", message: "amount must be positive integer") unless positive_integer?(@amount)
    raise BankError.new(code: "VALIDATION_FAILED", message: "cannot transfer to self") if @from_artist.id == @to_artist.id

    existing = LedgerTransaction.find_by(idempotency_key: @idempotency_key)
    return existing if existing

    ActiveRecord::Base.transaction do
      from_account = @from_artist.account.lock!
      to_account = @to_artist.account.lock!

      raise InsufficientBalanceError.new if from_account.balance_fuju < @amount

      tx = LedgerTransaction.new(
        kind: "transfer",
        idempotency_key: @idempotency_key,
        memo: @memo,
        metadata: @metadata,
        occurred_at: @occurred_at,
      )
      tx.entries.build(account: from_account, amount: -@amount)
      tx.entries.build(account: to_account, amount: @amount)
      tx.save!

      from_account.update!(balance_fuju: from_account.balance_fuju - @amount)
      to_account.update!(balance_fuju: to_account.balance_fuju + @amount)

      tx
    end
  rescue ActiveRecord::RecordNotUnique
    LedgerTransaction.find_by!(idempotency_key: @idempotency_key)
  end

  private

  def positive_integer?(value)
    value.is_a?(Integer) && value > 0
  end
end
```

## テスト要件

- `spec/services/ledger/transfer_spec.rb`
  - 正常系: A から B へ N 送金 → A 残高 -N、B 残高 +N
  - 正常系: `LedgerTransaction` が 1 件、`entries.sum(:amount) == 0`、`artifact_id` は NULL
  - 冪等性: 同一 `idempotency_key` を 2 回呼ぶと作成は 1 回
  - 異常系: A 残高不足 → `InsufficientBalanceError`、DB に `LedgerTransaction` が保存されない
  - 異常系: `from_artist == to_artist` → `BankError(VALIDATION_FAILED)`
  - 異常系: `amount <= 0` → `BankError(VALIDATION_FAILED)`
  - 並行性: 同一 Artist に対する同時 Transfer でも整合性が崩れない（`lock!` のスモーク確認。厳密テストは手動 or test-prof）

## 技術的な補足

- 残高不足時は `InsufficientBalanceError` を raise することでトランザクション全体が rollback され、
  DB 側の CHECK 制約（`balance_non_negative_for_artist`）に到達しない。CHECK は「最後の砦」。
- `from_account` と `to_account` を `lock!` する順序は、デッドロック回避のため
  **ID 昇順でロックするのが定石**。MVP では省略するが、本番規模では対応を検討（TODO を残す）。
- `memo` はユーザー入力。MVP では長さ制限なし（将来 255 文字制限を検討）。
- RuboCop: `raise InsufficientBalanceError.new` の `.new` は `Style/RaiseArgs: compact` によって明示が必要
  （`BankError` サブクラスで引数を取らない場合は `raise InsufficientBalanceError` の省略形でも OK、
  プロジェクトの一貫性を優先）。

## 非スコープ

- コントローラ（`POST /ledger/transfer`） → #17
- broadcast → #20
- デッドロック耐性の厳密テスト（MVP 外）

## 受け入れ基準

- [ ] `Ledger::Transfer.call(...)` が動作する
- [ ] 残高不足で rollback される
- [ ] 冪等性が担保されている
- [ ] RSpec / RuboCop が通る
