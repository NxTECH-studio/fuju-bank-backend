# 04: artists テーブル追加

> 依存: #02

## 概要

`artists` テーブルを `db/schema/artists.rb` に定義する。Artist は「ふじゅ〜の受け取り手」。

## 背景・目的

- 銀行ドメインの中核エンティティ。`Account` / `Artifact` / `LedgerTransaction` が全て Artist を起点に繋がる。
- HUD（作家 PWA）接続時の署名検証を将来実装するため、`public_key` カラムを先に用意しておく（MVP では未使用）。

## 影響範囲

- **変更対象**:
  - `db/schema/artists.rb`（新規）
  - `db/Schemafile`（require 行追加）
- **破壊的変更**: なし
- **外部層への影響**: なし（まだモデル・API は無い）

## スキーマ変更

### `artists` テーブル新規作成

```ruby
# db/schema/artists.rb

create_table "artists", force: :cascade do |t|
  t.string "name", null: false
  t.string "public_key", comment: "HUD 接続時の署名検証用。MVP では未使用"
  t.timestamps

  t.index ["name"]
end
```

- `name`: NOT NULL。表示名。
- `public_key`: NULL 許容。MVP では空で作成、将来 HUD 登録フロー追加時に埋める。
- index: 将来の名前検索用に `name` に張る（MVP では `id` 検索のみだが、コストは小さい）。

### `db/Schemafile` 更新

```ruby
require File.join(schema_dir, "artists")
```

## 実装ステップ

1. `db/schema/artists.rb` を新規作成（上記定義）
2. `db/Schemafile` の require 行のコメントアウトを解除
3. `make db/schema/apply` で dev + test DB に反映
4. `rails runner "p Artist.connection.tables.include?('artists')"` 相当のスモーク確認（別 PR の Artist モデルで担保されるので任意）

## テスト要件

- 本 PR ではモデルが無いため RSpec の追加は無し
- CI で `make db/schema/apply` が通ることが実質的な受け入れテスト

## 技術的な補足

- `force: :cascade` は Ridgepole 推奨。開発中のみ意味がある。
- `primary_key` は `bigint id` がデフォルトのため明示不要。
- `public_key` の長さ制限は MVP では設けない（PEM / JWK など形式を確定してから `limit:` を検討）。

## 非スコープ

- `Artist` モデルクラスの作成 → #09
- Artist 作成 API → #13

## 受け入れ基準

- [ ] `db/schema/artists.rb` が作成されている
- [ ] `db/Schemafile` で require されている
- [ ] `make db/schema/apply` が dev + test で成功する
- [ ] `psql` 等で `\d artists` を確認し、カラム構成が仕様通り
