# 23: lazy user プロビジョニング

> 依存: #21, #22

## 概要

JWT 検証成功時、`sub` に対応する `User` が無ければその場で作成する（lazy プロビジョニング）。
作成時は `User#after_create` によって `Account(kind: "user")` が 1 件同時に生まれる（#09 で実装済み）。

## 背景・目的

- 銀行側で事前にユーザー登録 API を叩かなくても、AuthCore で認証できたユーザーは
  自動的に銀行側 `User` + `Account` が生える方針（メモリ: `project_authcore_integration.md`）。
- `name` は AuthCore から取れない前提のため nil で作成し、
  HUD から別途 PATCH で埋める（本タスクでは PATCH は作らない）。

## 影響範囲

- **変更対象**:
  - `app/controllers/concerns/jwt_authenticatable.rb`（`current_user` 供給を追加）
  - `app/services/user_provisioner.rb`（新規 Service Object）
  - `spec/services/user_provisioner_spec.rb`（新規）
  - `spec/requests/authentication_spec.rb`（lazy 作成ケース追加）
- **破壊的変更**: なし
- **外部層への影響**: なし

## スキーマ変更

なし（#21 で `external_user_id` 追加済み、`name` nullable 化済み前提）

## 実装ステップ

1. `app/services/user_provisioner.rb` を新設
   ```ruby
   # JWT 検証後に呼ばれ、external_user_id に対応する User を返す。
   # 無ければ同一トランザクション内で User + Account(kind: "user") を作成する。
   class UserProvisioner
     def self.call(external_user_id:)
       new(external_user_id: external_user_id).call
     end

     def initialize(external_user_id:)
       @external_user_id = external_user_id
     end

     def call
       User.find_by(external_user_id: @external_user_id) || create_user!
     end

     private

     def create_user!
       ApplicationRecord.transaction do
         User.create!(external_user_id: @external_user_id, name: nil)
         # after_create :bootstrap_account! が Account を生成する
       end
       User.find_by!(external_user_id: @external_user_id)
     rescue ActiveRecord::RecordNotUnique
       # 並行リクエストで同一 sub の User が別トランザクションで先に作られたケース
       User.find_by!(external_user_id: @external_user_id)
     end
   end
   ```
2. `JwtAuthenticatable` concern に `current_user` を追加
   ```ruby
   def current_user
     @current_user ||= UserProvisioner.call(external_user_id: current_external_user_id)
   end
   ```
   - lazy evaluation: 参照されたタイミングで DB ヒット。コントローラで使わなければ DB 負荷なし。
3. `spec/services/user_provisioner_spec.rb` でケース網羅
4. `spec/requests/authentication_spec.rb` に lazy 作成ケースを追加
5. `make rspec` / `make rubocop` を通す

## テスト要件

- `spec/services/user_provisioner_spec.rb`
  - **新規作成**: 存在しない `external_user_id` で呼ぶと `User` が 1 件増え、`Account(kind: "user")` が同時に生える
  - **既存取得**: 既に存在する `external_user_id` で呼んでもレコードは増えず、同じ User を返す
  - **name は nil**: 新規作成された User の `name` は nil
  - **ULID 不正**: 不正な ULID で呼ぶと validation エラー（`ActiveRecord::RecordInvalid`）
  - **トランザクション境界**: Account 作成が失敗した場合、User も作成されない
    （`bootstrap_account!` 内で意図的に raise させるテスト）
  - **並行作成**: `RecordNotUnique` を rescue して再 find するフォールバックが効く
    （モックで 1 度目 create を `raise ActiveRecord::RecordNotUnique` にする）
- `spec/requests/authentication_spec.rb`
  - 新規 `sub` の JWT でリクエストすると、User が 1 件生えて 200
  - 同じ `sub` で 2 回目のリクエストは User は増えない

## 技術的な補足

- `find_or_create_by` ではなく明示的に `find_by → create!` に分けているのは、
  トランザクション境界と並行作成時の rescue を明示的に書きたいため。
- `after_create :bootstrap_account!` は User 作成と同一トランザクションで走るため、
  Account 作成失敗時は User ごとロールバックされる（#09 の設計通り）。
- 並行リクエストで同一 `sub` の User が同時に作られうる（認証直後の最初のリクエストが重複するケース）。
  `external_user_id` は unique index が張られているので、2 件目の insert は `RecordNotUnique` で
  失敗する。rescue してから find し直すことで冪等化する。
- 将来 introspection レスポンスの `username` を `name` のデフォルトとして使う選択肢もあるが、
  本タスクでは一律 nil。
- `ApplicationRecord.transaction` は `User.transaction` と等価だが、サービス層からは
  抽象側を呼ぶほうが意図が明確。

## 非スコープ

- HUD からの `name` PATCH API
- `public_key` 登録フロー
- AuthCore introspection で得た `username` を使った名前の自動セット
- System account 等の seed（別タスク）

## 受け入れ基準

- [ ] `UserProvisioner.call(external_user_id: ...)` で User + Account が自動生成される
- [ ] 既存ユーザーは再利用され、レコードは増えない
- [ ] 並行作成時に `RecordNotUnique` をハンドリングできる
- [ ] `JwtAuthenticatable#current_user` から User が取れる
- [ ] `make rspec` / `make rubocop` が通る
