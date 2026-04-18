# 05: artifacts テーブル追加

> 依存: #02, #04

## 概要

`artifacts` テーブルを `db/schema/artifacts.rb` に定義する。Artifact は発行（mint）の起点。

## 背景・目的

- ふじゅ〜は「どの作品に魂を削られたか」を記録する必要があり、`Artifact` が発行の起点となる。
- 物理場所（美術館の作品）と URL（Web 上の作品）の両方をサポートする（`location_kind` enum）。

## 影響範囲

- **変更対象**:
  - `db/schema/artifacts.rb`（新規）
  - `db/Schemafile`（require 追加）
- **破壊的変更**: なし
- **外部層への影響**: なし（MVP 時点では未公開）

## スキーマ変更

### `artifacts` テーブル新規作成

```ruby
# db/schema/artifacts.rb

create_table "artifacts", force: :cascade do |t|
  t.references "user", null: false, foreign_key: true, comment: "作者 User"
  t.string "title", null: false
  t.string "location_kind", null: false, comment: "physical / url"
  t.string "location_url", comment: "location_kind = 'url' の場合に必須"
  t.timestamps

  t.index ["user_id", "created_at"]
end
```

- `user_id`: FK。User が作者。
- `title`: NOT NULL。
- `location_kind`: 文字列 enum（`"physical"` / `"url"`）。Rails の `enum` でアプリ側にマッピングする（#10）。
- `location_url`: URL の場合に値が入る。物理作品では NULL。

### `db/Schemafile` 更新

```ruby
require File.join(schema_dir, "artifacts")
```

（`users` の require より後に書く。FK 依存のため順序重要）

## 実装ステップ

1. `db/schema/artifacts.rb` を新規作成
2. `db/Schemafile` の require 順序を確認しつつ追加
3. `make db/schema/apply` で反映

## テスト要件

- 本 PR ではモデルが無いため RSpec は不要
- `make db/schema/apply` が通ること

## 技術的な補足

- PostgreSQL の `ENUM 型` は使わず **文字列カラム + Rails enum** で扱う（Ridgepole の ENUM サポートが弱いため）。
- `location_kind` への CHECK 制約（`IN ('physical', 'url')`）は MVP ではモデル層の validation に任せ、DB 側は追加しない。
  将来、厳密性を上げたくなったら別タスクで CHECK 制約を追加する。
- `references` は `foreign_key: true` で外部キー制約を張る。

## 非スコープ

- `Artifact` モデル → #10
- Artifacts CRUD API → #15

## 受け入れ基準

- [ ] `db/schema/artifacts.rb` が作成されている
- [ ] `db/Schemafile` で `users` の後に require されている
- [ ] `make db/schema/apply` が dev + test で成功する
- [ ] FK が users を参照している
