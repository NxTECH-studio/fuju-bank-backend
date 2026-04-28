# B1: ActionCable Connection に JWT 認証を導入

## メタ情報

- **Phase**: 0（最優先）
- **並行起動**: ✅ 単独着手可能（他タスクと並列で進められる）
- **依存**: なし（B4 は本番疎通のみ後追いで OK）
- **同期点**: app セッションへ「JWT を `Sec-WebSocket-Protocol: bearer, <jwt>` の subprotocol で受け取る」を PR description で通知 → app A6 が追従

## 概要

`app/channels/application_cable/connection.rb` が現状 no-op、`UserChannel#subscribed` が `params[:user_id]` の存在確認のみ。`production.rb` で `disable_request_forgery_protection = true` を有効にしている以上、Connection レイヤで JWT 検証をしないと「他人の HUD を覗ける」状態。本タスクで Connection 層に AuthCore JWT 検証を入れる。

## 背景・目的

- 既存 `production.rb:97` 周辺に「AuthCore による接続認証を実装したら本設定とコメントを見直す」TODO あり。本タスクがその実装。
- AuthCore JWT の仕様は RS256 / `aud=authcore` / `iss=authcore` / `type=access` / `sub`=ULID 26 文字。bank の `JwtAuthenticatable` と同じ検証ロジックを Connection 側でも使う。

## 影響範囲

- ファイル:
  - `app/channels/application_cable/connection.rb`（実装本体）
  - `app/channels/user_channel.rb`（`stream_for current_user` に書き換え）
  - `app/controllers/concerns/jwt_authenticatable.rb`（共有可能なロジックを切り出し）
  - 新規 `app/services/authcore/jwt_verifier.rb`（任意。Connection / Controller 双方から呼ぶ service クラス）
  - `spec/channels/application_cable/connection_spec.rb`（新規）
  - `spec/channels/user_channel_spec.rb`（更新）
- 破壊的変更: あり。クライアントは `?user_id=` でなく JWT subprotocol で接続する必要がある。

## 既存実装の層構造（参考）

bank backend は既に以下の 3 層認証 concerns を持つ。Cable Connection は **JwtAuthenticatable 相当** のローカル JWT 検証層に揃える（introspection は呼ばない方針）。

| 層 | 場所 | 役割 |
| :--- | :--- | :--- |
| `JwtAuthenticatable` | ApplicationController | RS256 ローカル検証、`current_external_user_id` 供給 |
| `IntrospectionRequired` | LedgerController のみ | AuthCore `/v1/auth/introspect` で revocation / mfa 状態を確認 |
| `MfaRequired` | 未適用（MVP 未決） | introspection の `mfa_verified=true` 必須化 |

Cable Connection は **JwtAuthenticatable 相当のみ**（毎メッセージ introspection は重い + 接続中の revocation は別解で対応）。MFA 必須の Cable は将来的に `IntrospectionRequired` + `MfaRequired` を移植する形で拡張可能。

## 実装ステップ

1. **JWT 検証ロジックを切り出す**:
   - 既存 `JwtAuthenticatable#decode_and_verify!` を `Authcore::JwtVerifier.call(token:) -> claims` に切り出し（PORO）。`type=access` 必須、失敗時は `JWT::DecodeError` を `AuthenticationError` に変換。
   - `JwtAuthenticatable` 側もこの service を呼ぶよう書き換え（DRY）。

2. **`ApplicationCable::Connection` を実装**:
   - `identified_by :current_user`
   - `connect` で `Sec-WebSocket-Protocol` ヘッダから `bearer, <jwt>` を抽出 → `Authcore::JwtVerifier.call(token: jwt)` → `User.find_or_create_by!(external_user_id: claims["sub"])`（lazy provision を `UserProvisioner.call` に統一、B2 と整合）。
   - 失敗時は `reject_unauthorized_connection`。
   - サーバ側 subprotocol echo: ActionCable はデフォルトで `actioncable-v1-json` subprotocol を返すため、クライアントは `Sec-WebSocket-Protocol: actioncable-v1-json, bearer, <jwt>` のように並べる。Rails 側で `bearer` subprotocol を「**echo はせず受信時の認証情報としてのみ消費する**」運用にするのが安全（rack middleware で `Sec-WebSocket-Protocol` リクエストヘッダから token を抽出し、レスポンスは `actioncable-v1-json` のみを返す）。**実装中に動作確認が困難な場合は `Authorization` ヘッダ方式 (Ktor `request { header(HttpHeaders.Authorization, "Bearer $jwt") }`) にフォールバック**。判断は B1 の PR で確定し、app A6 に通知。

3. **`UserChannel` を `current_user` ベースに書き換え**:
   - `subscribed` から `params[:user_id]` を削除し、`stream_for current_user` に固定。これで自分の channel しか購読できなくなる。
   - 既存の `params[:user_id] != current_user.id` を reject する形でも良いが、シンプルさで `stream_for current_user` を推奨。

4. **`production.rb` のコメント更新**:
   - `disable_request_forgery_protection = true` の TODO コメント `# TODO: AuthCore による接続認証を実装したら本設定とコメントを見直す` を削除し「Connection レイヤで JWT 認証する前提」と明記。

5. **spec**:
   - `connection_spec.rb`: 正常 JWT で connect 成功 / 不正 JWT で reject / `type=refresh` で reject / 期限切れで reject / sub から User が lazy provision される。
   - `user_channel_spec.rb`: subscribe 時に `current_user` の broadcast がストリームされる。

## 検証チェックリスト

- [ ] `bundle exec rspec spec/channels/`
- [ ] 不正な JWT で `/cable` 接続が `reject` される
- [ ] `type=access` 以外の JWT は reject される
- [ ] 認証成功後、自分以外の `User` の broadcast を購読できない
- [ ] production.rb の TODO コメントを更新

## PR description テンプレート

```
## 同期通知（app セッション向け）
- JWT 配送: `Sec-WebSocket-Protocol: bearer, <jwt>` subprotocol（決定）
- フォールバック: subprotocol echo が困難な場合は `Authorization: Bearer <jwt>` ヘッダ方式に切替
- app A6 (`UserChannelClient`) を↑に合わせて改修してください
```
