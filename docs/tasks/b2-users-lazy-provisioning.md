# B2: Users#create を lazy provisioning に置き換え

## メタ情報

- **Phase**: 0
- **並行起動**: ✅ B1 と並列可能（共通の `UserProvisioner` を触るので軽いコンフリクトはあり得る）
- **依存**: なし
- **同期点**: app セッションへ「`POST /users/me` / `GET /users/me` の I/O サンプル」を PR description で通知 → app A2b が追従

## 概要

`UsersController#create` がクライアント params で `external_user_id` を受け取る暫定実装になっており、なりすましでユーザー作成可能。AuthCore JWT の `sub` から注入する形に置き換え、`POST /users/me` を idempotent に作って lazy provisioning 化する。

## 背景・目的

- 既存コメント `# 本番では AuthCore の JWT から取り出した sub を注入する形に置き換える。` の実装。
- AuthCore の `sub` は ULID 26 文字。`User.external_user_id` のスキーマがこれを受けられるか先に確認。

## 影響範囲

- ファイル:
  - `app/controllers/users_controller.rb`
  - `app/services/user_provisioner.rb`（拡張）
  - `app/controllers/application_controller.rb`（`current_user` ヘルパ追加）
  - `config/routes.rb`（`/users/me` 追加、`POST /users` を廃止）
  - `db/Schemafile`（必要なら `external_user_id` を string(26) に変更）
  - `spec/requests/users_spec.rb`（書き換え）
- 破壊的変更: あり。`POST /users { external_user_id, name, public_key }` は廃止。

## 既存実装の層構造（参考）

| 層 | 役割 | 本タスクでの扱い |
| :--- | :--- | :--- |
| `JwtAuthenticatable` | ローカル JWT 検証、`current_external_user_id` 供給 | **lazy provision はこの層で発火**（`POST /users/me` 限定） |
| `IntrospectionRequired` | LedgerController に適用済み | 触らない |
| `MfaRequired` | 未適用 | 触らない |

`POST /users/me` は登録ステップなので AuthCore の `/v1/auth/introspect` を呼ばずローカル JWT 検証だけで十分。LedgerController 等の金銭移動系は引き続き `IntrospectionRequired` で revocation チェックされる。

## 実装ステップ

1. **スキーマ確認**:
   - `User.external_user_id` のカラム型を確認。UUID 想定だったら ULID 26 文字 (`string` で十分) に変更可能か確認。
   - 必要なら ridgepole の `db/Schemafile` で `string(26), null: false, index: { unique: true }` に変更。
   - 既存データ (smoke test 用 `00000000-0000-0000-0000-000000000000` 等) は dev/test のみのはずなので reset で OK。

2. **`current_user` ヘルパを ApplicationController に追加**:
   - `JwtAuthenticatable` の `before_action :authenticate!` で取れる `current_external_user_id` から `User` を引く。
   - 未存在なら **「現リクエストが `POST /users/me` のときだけ」** lazy provision する。それ以外のエンドポイントで未存在なら 401 `UNAUTHENTICATED`（不正 token / 未プロビジョン状態を区別しない方針）。
   - `def current_user; @current_user ||= User.find_by(external_user_id: current_external_user_id); end`

3. **`UserProvisioner` 拡張**:
   - `UserProvisioner.call(external_user_id:, name: nil, public_key: nil)` を idempotent に（`find_or_create_by!`）。
   - 並行リクエストでの race condition 対策に `with_advisory_lock` または unique index + retry。

4. **`UsersController` 書き換え**:
   - `POST /users` を **廃止**。`POST /users/me` 新設（body: `{ name?, public_key? }`、`external_user_id` は body から削除）→ 既存なら 200、新規なら 201。常に provision 後の User を返す。
   - `GET /users/me` 新設（`current_user` を返す）。
   - `GET /users/:id` は `params[:id] == current_user.id` のみ許可、それ以外は 403 `FORBIDDEN`（または 404）。

5. **routes**:
   ```ruby
   resources :users, only: [] do
     collection do
       get :me, to: "users#show_me"
       post :me, to: "users#upsert_me"
     end
     resources :transactions, only: %i[index], controller: "user_transactions"
     member do
       get "", to: "users#show"
     end
   end
   ```
   実際の DSL は既存 routes.rb と整合する形に調整。

6. **spec 書き換え**:
   - `POST /users/me` を JWT 付きで叩いて 201 / 二度目は 200 / `external_user_id` を body で送っても無視されること。
   - `GET /users/:other_id` が 403 / 404。

## 検証チェックリスト

- [ ] `bundle exec rspec spec/requests/users_spec.rb`
- [ ] `external_user_id` を body で詐称しても無視される
- [ ] `POST /users/me` の二重呼び出しで重複 User が作られない（unique violation で落ちない）
- [ ] `GET /users/:other_id` で 403 / 404
- [ ] CLAUDE.md に新エンドポイントを反映

## PR description テンプレート

```
## 同期通知（app セッション向け）
新エンドポイント:
- POST /users/me: body `{ name?: string, public_key?: string }` → 200/201 `{ id, name, public_key, balance_fuju, created_at }`
- GET /users/me: → 200 同上
- POST /users (旧): 廃止
app A2b でログイン直後に `POST /users/me` を呼ぶ実装に変更してください。
```
