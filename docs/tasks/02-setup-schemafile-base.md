# 02: Schemafile フラット運用 / Ridgepole 運用定着

> 依存: なし（Phase 0）

## 概要

`db/Schemafile` 1 ファイルにテーブル定義をすべて直接書く**フラット運用**で進める。
以降のスキーマ追加タスク（#04〜#08）は `db/Schemafile` に `create_table` を追記する形で反映する。

## 背景・目的

- MVP / ハッカソン規模（テーブル 5 件程度）では、`db/schema/*.rb` に分割するメリットがコストを上回らない。
- FK 依存の順序は「書き順」で制御できる（参照先を先に書く）。Dir.glob のような自動読み込みに伴う順序問題も発生しない。
- 複雑化してきた（テーブル 15〜20 件超、複数人の並行開発で diff conflict が出る、等）時点でサブファイル分割に移行する方針とする。

## 影響範囲

- **変更対象**:
  - `db/Schemafile`（ヘッダコメントで運用方針を明記）
- **破壊的変更**: なし（まだテーブルは存在しない）
- **外部層への影響**: なし

## スキーマ変更

なし（この PR 自体では新規テーブルを追加しない。運用方針のみ）

## 実装ステップ

1. `db/Schemafile` のヘッダコメントを次のように書き換え、フラット運用の方針を明記する
   ```ruby
   # frozen_string_literal: true

   # Ridgepole schema definition
   #
   # テーブル定義はこのファイルに直接 create_table を並べる（フラット運用）。
   # MVP 規模のためサブファイル分割は行わない。複雑化してきたら `db/schema/*.rb` に分割する方針へ移行する。
   #
   # FK 依存があるテーブルは参照先を先に書くこと（例: users → accounts → ledger_transactions → ledger_entries）。
   # 反映コマンドは `make db/schema/apply`（dev + test 両環境に適用）。
   ```
2. `make db/schema/apply` が正常終了することを確認（テーブル 0 個の状態で apply が通る）

## テスト要件

- RSpec は特に追加不要（スキーマ定義変更のみ）
- `make db/schema/apply` に相当するステップが通ること

## 技術的な補足

- `create_table "users" do |t| ... end` のような Ridgepole DSL を Schemafile のトップレベルに書く。
- FK 制約は後続のテーブル定義で参照先が先にあることを前提にするため、**追記順序に注意**（参照先 → 参照元）。
- 分割に移行する場合は、別タスクとして Dir.glob ではなく明示 `require` で順序固定する設計に切り替える（将来検討）。

## 非スコープ

- 実テーブルの追加（#04 以降で順次 `db/Schemafile` に追記）
- サブファイル分割運用への移行（将来、複雑化してから検討）
- seed データの設計（#06 の system_issuance 口座で扱う）

## 受け入れ基準

- [ ] `db/Schemafile` にフラット運用の方針がヘッダコメントで明記されている
- [ ] `make db/schema/apply` が通る（テーブル 0 件での apply が成功する）
- [ ] RuboCop / RSpec が通る
