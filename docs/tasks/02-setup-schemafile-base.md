# 02: Schemafile サブファイル分割 / Ridgepole 運用定着

> 依存: なし（Phase 0）

## 概要

`db/Schemafile` をルートファイルとし、テーブル定義を `db/schema/*.rb` に分割する運用を整備する。
以降のスキーマ追加タスク（#04〜#08）はこの分割に従う。

## 背景・目的

- 現状 `db/Schemafile` はコメントのみ。テーブルが増えても単一ファイルで膨れると可読性が落ちる。
- Ridgepole は `require` でサブファイルを取り込めるため、テーブル単位で分割するのが自然。
- この運用ルールを最初に定着させ、以降のタスクで迷わないようにする。

## 影響範囲

- **変更対象**:
  - `db/Schemafile`（ルート。`require` のみ記述）
  - `db/schema/`（新規ディレクトリ）
  - `db/schema/.keep`（空ディレクトリを git 管理するため）
- **破壊的変更**: なし（まだテーブルは存在しない）
- **外部層への影響**: なし

## スキーマ変更

なし（この PR 自体では新規テーブルを追加しない。枠組みのみ）

## 実装ステップ

1. `db/schema/` ディレクトリを作成し、`db/schema/.keep` を置く
2. `db/Schemafile` を次のように書き換える
   ```ruby
   # frozen_string_literal: true

   # Ridgepole schema definition (root file)
   #
   # テーブル定義は db/schema/ 配下にサブファイルとして分割する。
   # 新しいテーブルを追加するときは、
   #   1. db/schema/<table_name>.rb を作成
   #   2. 下の require 一覧に追記
   # の順で反映する。反映コマンドは `make db/schema/apply`。

   schema_dir = File.expand_path("schema", __dir__)

   # Dir.glob による自動読み込みにすると順序が不定になり、FK 依存のあるテーブルで事故るため、
   # 明示的な require で順序を固定する。
   # require File.join(schema_dir, "artists")
   # require File.join(schema_dir, "artifacts")
   # require File.join(schema_dir, "accounts")
   # require File.join(schema_dir, "ledger_transactions")
   # require File.join(schema_dir, "ledger_entries")
   ```
3. README 的な説明は overview（`docs/tasks/00-overview.md`）に記載済みのため、コードコメントのみで十分
4. `make db/schema/apply` が正常終了することを確認（テーブル 0 個の状態で apply が通る）

## テスト要件

- RSpec は特に追加不要（スキーマ定義変更のみ）
- CI の `make db/schema/apply` に相当するステップが通ること

## 技術的な補足

- サブファイル内では `create_table "artists" do |t| ... end` のような Ridgepole DSL をトップレベルで書く。
- `Dir.glob` で自動読み込みすると、`ledger_entries` が `ledger_transactions` より先に読まれて FK エラーになる可能性があるため、
  順序を明示的に固定する設計にする。
- 各サブファイル冒頭に `# frozen_string_literal: true` は **不要**（RuboCop `Style/FrozenStringLiteralComment: Enabled: false`）。
- Ridgepole はこのファイルを普通に Ruby として eval するだけなので、`require` は相対パスでも動く。
  `File.expand_path` を使って絶対パス化しておくと `make db/schema/apply` と `bundle exec ridgepole` どちらでも動く。

## 非スコープ

- 実テーブルの追加（#04 以降で順次）
- seed データの設計（#06 の system_issuance 口座で扱う）

## 受け入れ基準

- [ ] `db/schema/` ディレクトリが作成され、`.keep` が入っている
- [ ] `db/Schemafile` は require スケルトンのみで、`make db/schema/apply` が通る
- [ ] RuboCop / RSpec が通る
