# 07: ledger_transactions テーブル追加

> 依存: #02, #05

## 概要

記帳ヘッダテーブル `ledger_transactions` を定義する。mint / transfer を 1 行で表現。

## 背景・目的

- 複式簿記のヘッダ部分。`LedgerEntry`（明細）を束ねる。
- `idempotency_key` によってマイニング層からの重複 POST を吸収する。
- `metadata` JSONB に「滞留秒数」「視線強度」等の文脈を保持し、後続の分析・SNS 層連携に使う。

## 影響範囲

- **変更対象**:
  - `db/schema/ledger_transactions.rb`（新規）
  - `db/Schemafile`（require 追加）
- **破壊的変更**: なし
- **外部層への影響**: なし（MVP の API 公開は #16, #17 で）

## スキーマ変更

### `ledger_transactions` テーブル新規作成

```ruby
# db/schema/ledger_transactions.rb

create_table "ledger_transactions", force: :cascade do |t|
  t.string "kind", null: false, comment: "mint / transfer"
  t.string "idempotency_key", null: false
  t.references "artifact", foreign_key: true, comment: "mint のとき必須、transfer は NULL"
  t.string "memo"
  t.jsonb "metadata", null: false, default: {}
  t.datetime "occurred_at", null: false, comment: "マイニング層での観測時刻"
  t.timestamps

  t.index ["idempotency_key"], unique: true
  t.index ["kind", "created_at"]
  t.index ["artifact_id", "created_at"]
end
```

- `kind`: 文字列 enum。Rails の `enum` で `mint` / `transfer` をマッピング（#11, #12 で）。
- `idempotency_key`: **ユニーク制約**。重複 POST 時は既存レコードを返すために使う。
- `artifact_id`: mint のとき必須、transfer は NULL（モデル層で validate）。
- `metadata`: JSONB、default `{}`。NULL ではなく空 JSON で。
- `occurred_at`: マイニング層が観測した時刻。`created_at`（銀行記帳時刻）とは別。

### `db/Schemafile` 更新

```ruby
require File.join(schema_dir, "ledger_transactions")
```

（`artifacts` の後、`ledger_entries` の前）

## 実装ステップ

1. `db/schema/ledger_transactions.rb` を作成
2. `db/Schemafile` の require 順序を調整
3. `make db/schema/apply` で反映

## テスト要件

- 本 PR ではモデル無しのため RSpec 不要
- `make db/schema/apply` が通ること
- `\d ledger_transactions` で `idempotency_key` のユニーク制約を確認

## 技術的な補足

- `jsonb` の default は **`{}` リテラル** ではなく `"{}"` 文字列でも動くが、Ridgepole は `{}` を受け入れて内部で PostgreSQL の `'{}'::jsonb` に展開する。
- `idempotency_key` は UUID / ULID を想定するが、値の形式は銀行側では強制しない（呼び出し側責任）。最大長制限も MVP では付けない。
- `kind` に対する DB CHECK 制約は付けず、モデルの `enum` に任せる（#07 以降でテーブル追加するたびに同様の方針）。

## 非スコープ

- `LedgerTransaction` モデル → #11 / #12 で部分的に、モデル単体としては #08 と合わせて整備
- mint / transfer のビジネスロジック → #11, #12

## 受け入れ基準

- [ ] `ledger_transactions` テーブルが作成される
- [ ] `idempotency_key` がユニーク
- [ ] `metadata` は JSONB / default `{}`
- [ ] `make db/schema/apply` が通る
