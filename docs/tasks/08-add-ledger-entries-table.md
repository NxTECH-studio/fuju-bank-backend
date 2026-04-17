# 08: ledger_entries テーブル追加

> 依存: #02, #06, #07

## 概要

記帳明細テーブル `ledger_entries` を定義する。`amount` は借方=正 / 貸方=負 で、
1 トランザクション内で SUM = 0 を（モデル層で）保証する。

## 背景・目的

- 複式簿記の明細部分。`LedgerTransaction` に対して 2 行以上の entry が紐付く。
- DB 側の SUM = 0 制約は deferred constraint などで実装可能だが、MVP はモデル層の validation で済ませる
  （性能・複雑性のトレードオフ）。

## 影響範囲

- **変更対象**:
  - `db/schema/ledger_entries.rb`（新規）
  - `db/Schemafile`（require 追加）
- **破壊的変更**: なし
- **外部層への影響**: なし

## スキーマ変更

### `ledger_entries` テーブル新規作成

```ruby
# db/schema/ledger_entries.rb

create_table "ledger_entries", force: :cascade do |t|
  t.references "ledger_transaction", null: false, foreign_key: true
  t.references "account", null: false, foreign_key: true
  t.bigint "amount", null: false, comment: "借方=正 / 貸方=負。SUM(amount) per transaction = 0"
  t.timestamps

  t.index ["account_id", "created_at"]
  t.index ["ledger_transaction_id"]
end

# amount が 0 であってはならない（意味のない entry を防ぐ）
execute <<~SQL.squish
  ALTER TABLE ledger_entries
    DROP CONSTRAINT IF EXISTS amount_non_zero;
SQL
execute <<~SQL.squish
  ALTER TABLE ledger_entries
    ADD CONSTRAINT amount_non_zero CHECK (amount <> 0);
SQL
```

- `amount`: `bigint`、`0` 禁止。
- `ledger_transaction_id`: FK、NOT NULL。
- `account_id`: FK、NOT NULL。
- index: account 別の履歴取得（#18）用に `(account_id, created_at)` を張る。

### `db/Schemafile` 更新

```ruby
require File.join(schema_dir, "ledger_entries")
```

（`ledger_transactions`, `accounts` の後）

## 実装ステップ

1. `db/schema/ledger_entries.rb` を作成
2. `db/Schemafile` の require 順序を調整（`accounts` → `ledger_transactions` → `ledger_entries`）
3. `make db/schema/apply` で反映
4. `\d ledger_entries` で制約を確認

## テスト要件

- 本 PR ではモデル層の実装は最小（タスク #11 / #12 で本格的に扱う）
- SUM = 0 のモデル検証は #11 / #12 で書く
- `make db/schema/apply` が通ること

## 技術的な補足

- SUM = 0 を **DB 側で強制** する場合:
  - deferred FK + trigger、あるいは `SET CONSTRAINTS ALL DEFERRED` + AFTER INSERT トリガーで可能
  - MVP ではコスト対効果を考えてモデル層で済ませる（`Ledger::Mint` / `Ledger::Transfer` サービスが唯一の書き込み経路）
- `amount_non_zero` CHECK は軽量で安全なので入れる。
- `ledger_transaction_id` の index は `t.references` が自動で作るため追加不要（上の `t.index ["ledger_transaction_id"]` は重複なので削除してよい。実装時に確認）。

## 非スコープ

- SUM = 0 のモデル validation → #11 / #12 の `LedgerTransaction` モデル整備で対応
- 残高キャッシュ更新ロジック → #11 / #12

## 受け入れ基準

- [ ] `ledger_entries` テーブルが作成される
- [ ] `amount_non_zero` CHECK 制約が張られている
- [ ] FK（`ledger_transaction_id`, `account_id`）が張られている
- [ ] `make db/schema/apply` が通る
