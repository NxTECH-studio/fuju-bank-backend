# STEP 01: `db/Schemafile` に `stores` テーブルと `accounts.store_id` を追加

- **前提 STEP**: なし（本 STEP が起点）
- **次の STEP**: [`02-store-model.md`](./02-store-model.md)
- **全体像**: [`00-overview.md`](./00-overview.md)

## 目的

店舗ドメインと店舗口座を DB レベルで表現する。Ridgepole でスキーマを更新し、`Store` モデルと `kind = 'store'` の Account を受け入れられる状態にする。

## 変更ファイル

- `db/Schemafile`

## スキーマ変更の詳細

1. **`stores` テーブルを新設**（`accounts` より前に定義する必要あり）
   - `code` (string, null: false, 一意) — QR に埋め込む店舗識別子（例: ULID 26 文字 or 任意の短い識別子）
   - `name` (string, null: false) — 店舗表示名
   - `signing_secret` (string, null: false) — 店舗個別の HMAC 秘密鍵。DB 保存前提（将来 Rails credentials 管理に移行可）
   - `active` (boolean, null: false, default: true) — 無効化フラグ
   - `timestamps`
   - `index [:code], unique: true`

2. **`accounts` に列追加**
   - `t.references "store", foreign_key: true, index: false` を追加
   - `kind = 'store'` のときに `store_id` 必須、`store_id IS NOT NULL` 部分ユニークインデックスを追加
     ```ruby
     t.index ["store_id"], unique: true, where: "store_id IS NOT NULL",
                           name: "index_accounts_on_store_id_unique_when_present"
     ```

3. **CHECK 制約の調整**
   - 既存 `balance_non_negative_for_user` は `kind <> 'user'` が評価条件。`store` 口座も非負にしたいので以下で置き換え:
     ```sql
     CHECK (kind = 'system_issuance' OR balance_fuju >= 0)
     ```
   - （オプション）`kind` 値の整合を DB 側でも縛るなら `CHECK (kind IN ('system_issuance','user','store'))` を追加。

## 作業内容

1. `stores` テーブルを `accounts` より前に定義（上記「スキーマ変更 1.」）
2. `accounts` に `t.references "store"` を追加
3. `accounts` に `store_id` 部分ユニークインデックスを追加
4. `balance_non_negative_for_user` CHECK 制約を `store` も非負対象にするよう置き換え

## 受け入れ基準

- `make db/schema/apply` が dev / test 両方で成功する
- `make db/reset` で再構築可能
- 既存の `system_issuance` 口座 seed / 既存データは破壊されない

## テスト観点

- スキーマ適用のみ。モデル仕様はこの STEP では触らない。
