# STEP 03: `Account` モデルに `kind = 'store'` を追加

- **前提 STEP**: [`02-store-model.md`](./02-store-model.md)（`Store` モデルが存在する）
- **次の STEP**: [`04-qr-signer-verifier.md`](./04-qr-signer-verifier.md)
- **全体像**: [`00-overview.md`](./00-overview.md)

## 目的

Account が Store に紐づけられるようにする。`kind = 'store'` の Account は `store_id` 必須、`user_id` は不可、残高は非負という制約を満たすようにする。

## 変更ファイル

- `app/models/account.rb`
- `spec/models/account_spec.rb`
- `spec/factories/accounts.rb`

## 作業内容

1. `KINDS` に `"store"` を追加
2. `belongs_to :store, optional: true`
3. `store_kind?` predicate 追加
4. `validates :store_id, presence: true, if: :store_kind?`
5. `validates :store_id, absence: true, unless: :store_kind?`
6. `validates :user_id, absence: true, if: :store_kind?`
7. 残高非負バリデーションを `store_kind?` でも有効化（現状の `user_kind?` と OR 条件に拡張 → `if: ->(a) { a.user_kind? || a.store_kind? }` またはメソッドに切り出し）
8. FactoryBot に `:store` trait を追加

## 受け入れ基準

- `account.kind = "store"` + `store: store` で create 可能
- `store` 口座で残高を負にしようとすると DB CHECK で弾かれる

## テスト観点

- `kind` ごとの user_id / store_id 要否
- store 口座の残高非負制約（DB レベルの `ActiveRecord::StatementInvalid` も含む）
