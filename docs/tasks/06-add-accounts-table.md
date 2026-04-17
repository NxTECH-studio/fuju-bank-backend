# 06: accounts テーブル追加 + system_issuance 口座 seed

> 依存: #02, #04

## 概要

`accounts` テーブルを定義し、ふじゅ〜発行源である `system_issuance` 口座を 1 行 seed する。

## 背景・目的

- 複式簿記の「勘定口座」を抽象化する中核テーブル。
- Artist 1 : Account 1 のリレーション（後続のモデル層で `after_create` 連動）。
- 発行の借方となる `system_issuance` 口座は **初期化時に必ず存在** する必要があるため、seed を Ridgepole で担保する（Rails の `db/seeds.rb` ではなく、Schemafile の `execute` 相当）。

## 影響範囲

- **変更対象**:
  - `db/schema/accounts.rb`（新規）
  - `db/Schemafile`（require 追加）
  - `db/seeds/system_accounts.rb`（新規、idempotent な seed スクリプト）
  - `Makefile`（`make db/seed` ターゲット追加を検討。MVP は `rails runner` で妥協可）
- **破壊的変更**: なし
- **外部層への影響**: なし

## スキーマ変更

### `accounts` テーブル新規作成

```ruby
# db/schema/accounts.rb

create_table "accounts", force: :cascade do |t|
  t.references "artist", foreign_key: true, comment: "kind = 'artist' のときに必須"
  t.string "kind", null: false, comment: "system_issuance / artist"
  t.bigint "balance_fuju", null: false, default: 0, comment: "残高キャッシュ（entries SUM と一致させる）"
  t.timestamps

  t.index ["kind"]
  t.index ["artist_id"], unique: true, where: "artist_id IS NOT NULL",
    name: "index_accounts_on_artist_id_unique_when_present"
end

# CHECK 制約: Artist 口座は残高が負になってはいけない
# system_issuance は発行源なので常にマイナス、よって条件付き制約にする
execute <<~SQL.squish
  ALTER TABLE accounts
    DROP CONSTRAINT IF EXISTS balance_non_negative_for_artist;
SQL
execute <<~SQL.squish
  ALTER TABLE accounts
    ADD CONSTRAINT balance_non_negative_for_artist
    CHECK (kind <> 'artist' OR balance_fuju >= 0);
SQL
```

- `artist_id`: `system_issuance` では NULL、`artist` では必須 & ユニーク。
  → 部分ユニークインデックスで 1:1 を担保。
- `kind`: 文字列 enum。将来 `user`（鑑賞者）や `fee`（手数料口座）を追加可能。
- `balance_fuju`: `bigint`、default 0。
- **CHECK 制約**: `kind = 'artist'` のときだけ `balance_fuju >= 0`。`system_issuance` は発行原資なので負値 OK。

### seed（system_issuance 口座）

```ruby
# db/seeds/system_accounts.rb
#
# 使い方: bin/rails runner db/seeds/system_accounts.rb
# 何度実行しても安全（idempotent）

system_account = Account.find_or_create_by!(kind: "system_issuance", artist_id: nil)
puts "system_issuance account: id=#{system_account.id}, balance=#{system_account.balance_fuju}"
```

- 本 PR ではファイルを置くだけで OK（`Account` モデルは #09 以降で作るため、この時点では実行できない）。
- モデルタスク完了後、`make db/setup` 的なターゲットに組み込む（別タスクで検討）。

### `db/Schemafile` 更新

```ruby
require File.join(schema_dir, "accounts")
```

## 実装ステップ

1. `db/schema/accounts.rb` を作成（CHECK 制約含む）
2. `db/Schemafile` に require 追加
3. `db/seeds/system_accounts.rb` を作成
4. `make db/schema/apply` で反映
5. `psql` で CHECK 制約が張られたことを確認：
   ```sql
   SELECT conname FROM pg_constraint WHERE conrelid = 'accounts'::regclass;
   ```

## テスト要件

- 本 PR ではモデル層が無いためアプリ側の RSpec は無し
- `make db/schema/apply` が通ること
- 将来 #09 完成後に seed を実行して CHECK 制約を踏まないことを確認

## 技術的な補足

- `execute` を使った CHECK 制約の書き方は Ridgepole 標準。`DROP IF EXISTS` を先に実行することで冪等。
- PostgreSQL の部分インデックス `where: "artist_id IS NOT NULL"` は Rails 標準で書ける。
- `balance_fuju` を `bigint` で明示する理由: Rails 8 の default integer は `int4` のため、将来の桁あふれを避けるために `bigint`。
- CHECK 制約のエラーは `ActiveRecord::StatementInvalid` として飛んでくるため、`Ledger::Transfer` サービスで残高不足判定を **モデル層でも事前チェック** する（二重防衛）。

## 非スコープ

- `Account` モデル → #09
- balance_fuju の突合ジョブ（MVP 外）

## 受け入れ基準

- [ ] `accounts` テーブルが作成される
- [ ] `balance_non_negative_for_artist` CHECK 制約が張られている
- [ ] `artist_id` の部分ユニーク制約が張られている
- [ ] `db/seeds/system_accounts.rb` が作成されている（実行は後続 PR）
- [ ] `make db/schema/apply` が成功する
