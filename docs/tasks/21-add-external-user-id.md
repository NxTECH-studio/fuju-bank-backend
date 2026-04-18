# 21: users.external_user_id 追加 + name nullable 化

> 依存: #04, #09

## 概要

AuthCore との連携に向け、`users` テーブルに `external_user_id`（AuthCore の `sub` = ULID）カラムを追加し、
`name` を nullable 化する。`public_key` は本タスクでは触らない。

## 背景・目的

- AuthCore を一次認証基盤とする方針（メモリ: `project_authcore_integration.md`）。
  銀行側 `User` を AuthCore の `sub`（ULID, 26 文字）で同定するため、
  永続キーとしての `external_user_id` が必要。
- lazy プロビジョニング時点では AuthCore から表示名が来ない前提のため、
  `users.name` を nullable 化して nil で作成可能にする。HUD からの後続 PATCH で埋める。
- `public_key` 周りの整理（NOT NULL 化 / comment 更新 / JWK 形式確定）は
  スコープが別なので将来タスクに回す。

## 影響範囲

- **変更対象**:
  - `db/Schemafile`（`users` テーブル定義の更新）
  - `app/models/user.rb`（validation 更新）
  - `spec/models/user_spec.rb`（ケース追加）
  - `spec/factories/users.rb`（`external_user_id` を sequence で付与）
- **破壊的変更**: `users.name` の NOT NULL 解除（後方互換。既存 row は影響なし）
- **外部層（マイニング / SNS）への影響**: なし（この時点では参照 API が外部公開されていない）

## スキーマ変更

### `users` テーブル更新（`db/Schemafile`）

```ruby
create_table "users", force: :cascade do |t|
  t.string "external_user_id", null: false, limit: 26,
                               comment: "AuthCore の sub。ULID 26 文字"
  t.string "name", comment: "表示名。lazy プロビジョニング時は NULL、HUD から後続 PATCH で設定"
  t.string "public_key", comment: "HUD 接続時の署名検証用。MVP では未使用"
  t.timestamps

  t.index ["external_user_id"], unique: true
  t.index ["name"]
end
```

変更点:

- `external_user_id` を追加（NOT NULL, `limit: 26`, unique index）
- `name` から `null: false` を外し、comment を追記
- 既存の `name` index は維持

### 既存 row のマイグレーション

- dev / test は `make db/schema/apply` で再適用すれば済む（開発データのみ）
- 本番投入時点では `users` レコードは存在しない想定（#04 投入済みだがユースケース前）。
  データが入っていれば別途バックフィル PR を切る（本タスクの非スコープ）。

## 実装ステップ

1. `db/Schemafile` の `users` 定義を上記に差し替える
2. `make db/schema/apply` で dev + test に反映し、`\d users` で制約・index を確認
3. `app/models/user.rb` の validation を更新
   ```ruby
   ULID_REGEX = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

   validates :external_user_id, presence: true,
                                uniqueness: true,
                                format: { with: ULID_REGEX, }
   # name の presence validation は削除（DB 側も nullable 化）
   ```
4. `spec/factories/users.rb` を更新
   ```ruby
   factory :user do
     sequence(:external_user_id) { |n| ULID.generate }  # or 固定 ULID を n で差し替え
     sequence(:name) { |n| "User #{n}" }
   end
   ```
   - `ulid` gem が未導入ならベタ書きの ULID 文字列を sequence で生成する
5. `spec/models/user_spec.rb` にケースを追加
   - `external_user_id` が ULID 形式でないと invalid
   - 重複 `external_user_id` で invalid
   - `name` が nil でも valid（lazy 作成ケース）
   - 既存: Account 自動生成 / destroy restrict は引き続き通ること
6. `make rspec` / `make rubocop` を通す

## テスト要件

- `spec/models/user_spec.rb`
  - `create(:user)` が通る（factory 更新の確認）
  - `build(:user, external_user_id: nil)` が invalid
  - `build(:user, external_user_id: "invalid")` が invalid（ULID 形式）
  - `build(:user, external_user_id: "01HYZ...")` + 同値の 2 件目作成で uniqueness エラー
  - `build(:user, name: nil)` が **valid**（nullable 化の確認）
- Schemafile 反映後に `make db/schema/apply` が冪等に通ること

## 技術的な補足

- ULID 正規表現は Crockford Base32（`I`, `L`, `O`, `U` 除外）を使う。
- `ulid` gem（例: `ruby-ulid`）の導入は本タスクでは必須ではない。lazy 作成側（#23）で
  AuthCore の `sub` をそのまま保存するだけなので、banking 側で ULID 生成は不要。
- `external_user_id` は一度決まったら不変の想定。更新させる API は今後も作らない。
- `name` index は nullable 化しても問題なく機能する（NULL はインデックスから除外されるだけ）。
- `public_key` は既存のまま（NULL 許容、comment 維持）。整理は別タスクで。

## 非スコープ

- `public_key` の NOT NULL 化 / comment 更新 / 形式確定
- JWT 検証の concern 実装 → #22
- lazy プロビジョニング（find_or_create_by）の実装 → #23
- 既存本番データのバックフィル（現状データが無い前提）

## 受け入れ基準

- [ ] `db/Schemafile` が更新され、`make db/schema/apply` が成功する
- [ ] `users.external_user_id` が NOT NULL + unique index 付きで作成されている
- [ ] `users.name` が nullable になっている
- [ ] User モデルの validation（presence / uniqueness / ULID format）が効く
- [ ] `name` が nil でも User 作成が通る
- [ ] `make rspec` / `make rubocop` が通る
