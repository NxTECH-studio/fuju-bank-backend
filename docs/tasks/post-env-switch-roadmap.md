# post-env-switch-roadmap: env 切り替え後に本番稼働まで必要な実装計画（backend 側）

## 概要

`prod-action-cable-solid-adapter-and-origins.md` で production の ActionCable / allowed_request_origins / hosts は揃い、本番 `https://api.fujupay.app` も既にデプロイ稼働中（`.github/workflows/cd.yml` が main push で Proxmox CT に Tailscale + SSH で `docker compose -f compose.prod.yml up -d --build` する CD パイプライン）。一方でアプリを本番に向けて配布するには、**認証 / プロビジョニング / 本番 ENV の追加投入** の 3 領域が未完。本ドキュメントは残作業を依存順で並べた実装計画書。

各タスクは原則 1 PR = 1 サブドキュメント (`docs/tasks/B*-*.md`) に分割して `/start-with-plan` で流す前提で章立てしている。

## AuthCore の現状（前提）

> 認証基盤は別リポジトリで既に存在する。詳細は `/Users/ryota/Documents/works/proj-fuju/fuju-system-authentication/README.md`。

- **実装済み**: Go 製の独立サービス。クリーンアーキテクチャ + クリーン Phase 0〜8 のロードマップ（README §9）。
- **JWT 仕様**: RS256 / `aud=authcore` / `iss=authcore` / `type=access | refresh | pre` 必須 / `sub` = ULID 26 文字。Access TTL 15 分 / Refresh TTL 30 日 / Pre 10 分。
- **Refresh Token は HttpOnly cookie 配送** (`Path=/v1/auth; SameSite=Lax; Secure`)。**ボディには返さない**。これはネイティブクライアント設計に強く効くので app セッション側で別途対応必要（§ app A1/A2 参照）。
- **Login API**: `POST /v1/auth/login` / body `{ identifier, password }`（メール or 公開ID）→ MFA 無しなら `{ access_token, token_type, expires_in }` + `Set-Cookie: refresh_token=...` / MFA 有りなら `{ pre_token, mfa_required: true, ... }`。
- **Introspection**: `POST /v1/auth/introspect` Basic Auth + form (`token=<jwt>`) → RFC 7662 (`active`, `sub`, `mfa_verified` 等)。**bank 側 `Authcore::IntrospectionClient` は既にこれに準拠している**。
- **bank backend に必要な ENV**: `AUTHCORE_BASE_URL` / `AUTHCORE_CLIENT_ID` / `AUTHCORE_CLIENT_SECRET` / `AUTHCORE_JWT_PUBLIC_KEY` / `AUTHCORE_EXPECTED_AUDIENCE`(default: authcore) / `AUTHCORE_EXPECTED_ISSUER`(default: authcore)。
- **既存の認証 concerns 層**: bank backend は既に 3 層で構成済み:
  - `JwtAuthenticatable`（ApplicationController 全適用、ローカル JWT 検証 + `current_external_user_id` 供給）
  - `IntrospectionRequired`（LedgerController のみ、AuthCore introspection で revocation / mfa_verified 状態確認）
  - `MfaRequired`（concern は存在するが未適用、`introspection_result.mfa_verified?` 必須化）
- **`mfa_verified` semantics** (api-summary §4.4): per-token / per-session。「`false` を MFA 未設定と解釈してはいけない」。MfaRequired を適用する判断は別タスク（MVP では未決定、`ledger_controller.rb:3` のコメント参照）。

## アプリ側の現状（前提）

> 本ロードマップを進める上で前提となる app 側の実態。詳細は `fuju-bank-app/docs/tasks/post-env-switch-roadmap.md` を参照。

- **shared 層は完成**: KMP の Repository / Api / DTO / DI / TokenStorage / HttpClientFactory は揃っている。BuildKonfig による `BANK_API_BASE_URL` / `CABLE_URL` の Debug/Release 切替も完了。
- **UI は実質ゼロ**: iOS / Android どちらも「Click me!」「Smoke test: UserApi.get」だけ。ログイン / 残高 / 送金 / 履歴 / HUD / Artifact 投稿の画面は未実装。
- **AUTHCORE_BASE_URL のみ未対応**: shared/.../NetworkConstants.kt にハードコード。本ロードマップ B4 で確定する URL に合わせて A1 で BuildKonfig 化される予定。
- **backend 側に効いてくるタイミング**:
  - **B1 (Cable JWT 認証)**: subprotocol / query のどちらで JWT を載せるか確定したら、app 側 `UserChannelClient` がそれに合わせる。**B1 PR の中で I/O 仕様を確定 → app 側に通知**。
  - **B2 (Users lazy provisioning)**: `POST /users/me` の I/O が確定したら、app 側 A2 のログイン直後フローがそれに合わせる。
  - **B4 (AuthCore のデプロイ)**: `fuju-system-authentication` を本番にデプロイし、bank の client 登録を行い、`AUTHCORE_BASE_URL` / `AUTHCORE_JWT_PUBLIC_KEY` / `AUTHCORE_CLIENT_*` 確定値を共有する（新規構築ではない）。
  - **B5 (CD への ENV 注入)**: B1 / B2 / B4 を本番でもオンにするための実体作業。本番 boot 失敗を避けるため B1/B2 と必ずセット PR にする。

## 並列セッション（app セッション / backend セッション）作業ガイド

> Claude Code を 2 セッション並列で動かす場合の役割分担と同期ポイント。

- **backend セッション（このドキュメント）が単独で進められるタスク**:
  - B1 / B2 / B3 / B5 の **Rails 側実装と spec** → app 側を待たずに着手可能。
  - B4（AuthCore のデプロイ + client 登録）→ AuthCore リポジトリと bank リポジトリの両方を触るが、bank 単独のロードマップ範囲で完結（AuthCore 仕様自体は変更しない前提）。
  - B6（E2E 疎通スクリプト）→ アプリ UI を呼ばず直接 HTTP / WebSocket を叩くスクリプトで完結。
- **app セッションの完了を待つタスク**:
  - 基本的に無し。B 系は backend だけで閉じている。**ただし B1 / B2 で I/O 仕様を変えるなら、変更内容を PR description に明記して app セッションに伝える責任が backend セッションにある**。
- **同期点（両セッションで合意が必要）**:
  - **AUTHCORE_BASE_URL 値**: B4 で確定 → app A1 の release 値として共有。
  - **JWT を Cable に乗せる方法**: B1 で決定（subprotocol or query）→ app A6 が追従。**B1 のサブタスク化時にここを最初に決めて PR description に書く**。
  - **`POST /users/me` の I/O 仕様**: B2 で確定 → app A2 が追従。リクエスト body / レスポンス JSON のサンプルを PR description に書く。
- **コンフリクト回避**:
  - backend セッションは原則 `fuju-bank-backend/` 配下のみを触る。`fuju-bank-app/` は触らない。
  - shared 側 DTO の追従が必要な変更（B2 で `users#create` の I/O が変わる等）は app セッション側に Issue / PR description で依頼する形にする。

## 依存関係サマリ

```
B1 (Cable Connection JWT) ─┐
                            ├─→ B6 (E2E 疎通) ─→ 本番リリース
B2 (Users lazy provision) ─┤
B3 (CORS 方針)              │
B4 (AuthCore deploy + client 登録) ──┤   ※ B4 は B1/B2 のテストで必要
B5 (CD への ENV 注入 等)  ──┘
```

- アプリ側 `post-env-switch-roadmap.md` の **A2b (ログイン UI 本番疎通)** は B2 + B4 + B5 が前提。**A2a (shared 層改修)** はローカル AuthCore で先行可能。
- アプリ側 **A6 (リアルタイム HUD)** は B1 が前提。

---

## 実装順序（Phase 別）

### Phase 0: 認証の足回り（最優先・直列）

> production.rb で `disable_request_forgery_protection = true` を入れた以上、Cable 側の認証を塞がないと「他人の HUD を覗ける」状態。最優先。

#### B1. ActionCable Connection で JWT 認証を行う

- **Why**: `application_cable/connection.rb` が現状 no-op、`UserChannel#subscribed` が `params[:user_id]` の存在確認のみ。disable_request_forgery_protection を有効にしているので、Connection レイヤで JWT を検証しないと攻撃面が出る。
- **対象ファイル**:
  - `app/channels/application_cable/connection.rb`
  - `app/channels/user_channel.rb`
  - `spec/channels/...`
- **JWT 仕様（AuthCore 準拠）**:
  - RS256 / `type=access` / `aud=authcore` / `iss=authcore` / `sub` = ULID (26 文字)
  - 検証は既存 `JwtAuthenticatable#decode_and_verify!` のロジックを Connection 側に移植（JWT::DecodeError → reject）
- **実装ポイント**:
  - 接続時に **subprotocol ヘッダ** で JWT を受け取る方針を採用する（`Sec-WebSocket-Protocol: bearer, <jwt>`）。ブラウザ Origin の制約で query string (`?token=`) は URL ログ漏洩リスクが高く、ネイティブからも subprotocol の方が綺麗（Ktor の `WebSocketSession` で `request { headers.append("Sec-WebSocket-Protocol", "bearer, $jwt") }` で渡せる）。
  - `JwtAuthenticatable#decode_and_verify!` をモジュール関数 or service クラス (`Authcore::JwtVerifier` 等) に切り出して Connection / Controller 双方から呼ぶ。
  - 検証成功時は `current_user` (= `User.find_by(external_user_id: claims["sub"])` を **lazy provision 込みで** 取得) を `identified_by :current_user` で確立。これは B2 と同じヘルパに集約する。
  - `UserChannel#subscribed` は `current_user.id != params[:user_id]` を reject する不変条件に変える。**または `params[:user_id]` を削除して `stream_for current_user` に固定する** のが安全（自分の channel しか購読できなくなる）。
- **同期点（app セッション側に通知）**:
  - JWT 配送方式: `Sec-WebSocket-Protocol: bearer, <jwt>`
  - subprotocol を採用したら server 側もそれを echo する必要がある（Rails / Action Cable の `protocols` 設定確認）。
- **関連 TODO**: `production.rb:97` のコメントを実装済みに合わせて更新。

#### B2. Users#create を lazy provisioning に置き換え

- **Why**: 現状 `external_user_id` をクライアント params で受け取っており、コメントに「暫定」と明記。AuthCore の sub から注入する形に変えないと、なりすまし作成が可能。
- **対象ファイル**:
  - `app/controllers/users_controller.rb`
  - `app/services/user_provisioner.rb`（既存・拡張）
  - `app/controllers/concerns/jwt_authenticatable.rb`（必要なら lazy provision 呼び出しを生やす）
  - `config/routes.rb`（`POST /users/me` 追加）
- **AuthCore との接続**:
  - `current_external_user_id` (= `claims["sub"]`) は ULID 26 文字。`User.external_user_id` のスキーマがこれを受けられるか確認（既存スキーマは UUID 想定の可能性あり → ridgepole で string(26) に変える必要があるかも）。
  - AuthCore の `username` (= public_id, 4-16 文字英数字) を bank の `User.name` に同期する/しないの方針決定（暫定: 同期しない、bank 側で別途 name を持つ）。
- **実装ポイント**:
  - `before_action :authenticate!` で取得した `current_external_user_id` を使い、未存在なら `UserProvisioner.call(external_user_id: ..., name: nil, public_key: nil)` で作成する `current_user` ヘルパを ApplicationController に置く。
  - `POST /users/me` (新設) は idempotent: 二重呼びでも 200 を返す（既存なら return、無ければ provision）。**body は `{ name?, public_key? }` のみ受ける**（`external_user_id` は body から削除、JWT sub から注入）。
  - `UsersController#create` は廃止。`UsersController#show` は `params[:id] == current_user.id` のみ許可（または `/users/me` の GET を作り、`/users/:id` は将来の他人参照用途に温存）。
- **同期点（app セッション側に通知）**:
  - 新エンドポイント: `POST /users/me` / `GET /users/me` の I/O サンプル JSON を PR description に書く。

#### B3. CORS の方針決定と適用

- **Why**: `config/initializers/cors.rb` がフルコメントアウト。ネイティブアプリのみなら不要だが「不要」と明示しないと将来事故る。SNS / マイニング層から WebView 経由で叩かれる可能性も含めて方針を決める。
- **判断分岐**:
  - ネイティブのみ → `cors.rb` を残してコメントで「ネイティブクライアントのみのため CORS 不要」と明記、`rack-cors` Gem も削除を検討。
  - WebView/ブラウザあり → `https://*.fujupay.app` 系のみ許可で初期化子を有効化。
- **対象ファイル**: `config/initializers/cors.rb`, `Gemfile`（gem 削除する場合）。

### Phase 1: AuthCore 本体とデプロイ実体（並行可能）

#### B4. AuthCore のデプロイと bank クライアント登録

- **前提（実態）**:
  - **AuthCore は `/Users/ryota/Documents/works/proj-fuju/fuju-system-authentication` に実装済みの Go サービス**（クリーンアーキテクチャ、Phase 0〜8 のロードマップ済み）。新規構築タスクではない。
  - bank backend 側の `Authcore::IntrospectionClient` は既に RFC 7662 準拠（`POST /v1/auth/introspect` + Basic Auth + form）で正しく実装されている。
  - `Authcore` initializer の `expected_audience` / `expected_issuer` のデフォルト `authcore` は AuthCore の JWT デフォルトと整合（README §3.6: `aud: "authcore"`）。
  - JWT は **RS256**、`type=access` 必須、`sub` は ULID (26 文字)。これも `JwtAuthenticatable` の現状実装と整合する。
- **Why**: 本番運用に乗せるには AuthCore のデプロイ実体と bank の client 登録が必要。
- **やること**:
  1. **AuthCore 自体のデプロイ**: `fuju-system-authentication` を本番にデプロイ（Proxmox CT に同居 or 別 CT、`https://authcore.fujupay.app` で受ける、TLS 終端は bank と同じ ホスト reverse proxy 想定）。鍵ペアは KMS / Secret Manager 経由 or サーバー内 `keys/` 配置で `JWT_KEY_PATH` から読ませる。
  2. **bank の client 登録**: AuthCore の `clients` テーブルに `client_id=fuju-bank-backend` (仮) で row を作り、`client_secret` を Argon2id ハッシュで保存。発行した平文 secret を bank の `AUTHCORE_CLIENT_SECRET` に投入する。AuthCore 側に admin スクリプト or seed があるか確認する（無ければ AuthCore 側に rake / cmd を追加）。
  3. **公開鍵配布**: AuthCore が起動時に読む `keys/jwt.public.pem` の中身を bank の `AUTHCORE_JWT_PUBLIC_KEY` に同期するパイプラインを決める（手動コピー → 鍵ローテーション時にミスりやすいので、将来は AuthCore 側に `/v1/auth/jwks` 相当のエンドポイントが入るまで暫定運用）。
  4. **疎通スクリプト**: `script/check_authcore.rb` で「register → login → introspect」を 1 コマンドで通す。
- **成果物**:
  - 本番 AuthCore CT への deploy 手順（AuthCore 側 `docs/runbooks/deploy.md` も新規）
  - bank 側 `AUTHCORE_BASE_URL=https://authcore.fujupay.app` / `AUTHCORE_CLIENT_ID` / `AUTHCORE_CLIENT_SECRET` / `AUTHCORE_JWT_PUBLIC_KEY` の本番投入（B5 と連動）
  - `script/check_authcore.rb`
- **アプリ側との同期**: `https://authcore.fujupay.app` を app A1 の release 値として共有。

#### B5. 既存 CD への AuthCore ENV 注入 / Solid Queue worker 追加 / ドキュメント更新

- **前提（実態）**:
  - 本番は **Kamal ではなく** `.github/workflows/cd.yml` が `main` push で Tailscale + SSH 経由で Proxmox CT に入り、`docker compose -p fuju-bank-prod -f compose.prod.yml up -d --build` → ridgepole apply、で動いている。
  - `compose.prod.yml` には `db` (postgres:17) と `web` (Rails) のみ。`127.0.0.1:3000` にバインドしているので、ホスト側 reverse proxy が `api.fujupay.app` の TLS 終端をしている。
  - `CLAUDE.md` の「デプロイ: Kamal」記述は古いので、本タスクで実態に揃える。
- **Why**: B1 / B2 で AuthCore JWT 検証 / introspection が走るようになると、`AUTHCORE_JWT_PUBLIC_KEY` / `AUTHCORE_BASE_URL` / `AUTHCORE_CLIENT_ID` / `AUTHCORE_CLIENT_SECRET` / `AUTHCORE_EXPECTED_AUDIENCE` / `AUTHCORE_EXPECTED_ISSUER` が production で未設定なら起動時に `KeyError` で落ちる。Solid Queue worker も現状 compose.prod.yml に独立サービスとして無いので、ジョブが消化されない可能性がある。
- **対象ファイル / 成果物**:
  - `.github/workflows/cd.yml`（`env:` と `appleboy/ssh-action` の `envs:` に AUTHCORE_* を追加）
  - `compose.prod.yml`（web service の `environment:` に AUTHCORE_* を追加。必要なら `worker` サービスを追加）
  - GitHub Repository Settings → Secrets / Variables（`AUTHCORE_JWT_PUBLIC_KEY` / `AUTHCORE_CLIENT_SECRET` を Secret、それ以外を Variable）
  - `CLAUDE.md`（「デプロイ: Kamal」を「GitHub Actions cd.yml + docker compose on Proxmox CT (Tailscale + SSH)」に書き換え）
  - `docs/runbooks/deploy.md`（新規・現状 CD の手順 / ロールバック / secrets ローテーション手順）
- **実装ポイント**:
  - Solid Queue は現状 `web` プロセスと同居か別 service かを `config/queue.yml` / Procfile から確認。別 service にする場合 `compose.prod.yml` に `worker:` を追加し `bundle exec rake solid_queue:start` を回す。
  - Solid Cable のテーブルは ridgepole 管理外。初回デプロイ時に `rails db:migrate` で `solid_cable_messages` を作る必要があるかを確認し、必要なら cd.yml に 1 回限りの migrate ステップを追加。
  - `AUTHCORE_JWT_PUBLIC_KEY` は改行を含む PEM。GH Secrets で改行入りで保存し、`appleboy/ssh-action` に渡す際にエスケープが壊れないか動作確認（必要なら base64 で渡して docker 側でデコード）。

### Phase 2: 統合検証（B1〜B5 の merge 後）

#### B6. 認証 E2E 疎通テスト

- **Why**: 個別タスクは緑でも、AuthCore → bank → UserChannel まで本番ドメインで一度通したことがない状態。B1〜B5 のリグレッションを早期検出する仕組みが要る。
- **成果物**:
  - `script/e2e_smoke.rb`（or shell）: AuthCore でログイン → bank `POST /users/me` → `GET /users/:id` → `POST /ledger/transfer` → `wss://.../cable` 接続で broadcast 受信、までを 1 コマンドで通す。
  - GitHub Actions で nightly に走らせる（必要なら staging 専用 ENV）。
- **判定基準**: 全ステップが緑、Cable で broadcast が 5 秒以内に受信できる。

---

## 検証チェックリスト（リリース前）

- [ ] B1: 不正な JWT で `/cable` に接続すると `subscribed` 前に切られる（rspec で）
- [ ] B1: 他人の `user_id` で subscribe しようとすると reject される
- [ ] B2: AuthCore JWT のみで `POST /users/me` が成功し、二重呼びでも 200 を返す（idempotent）
- [ ] B2: `external_user_id` を body で詐称しても無視される
- [ ] B3: ネイティブからの呼び出しは CORS preflight 不要で通る
- [ ] B4: `https://api.fujupay.app/up` が 200 / Authcore introspection が疎通する
- [ ] B5: cd.yml に AUTHCORE_* が注入され、Solid Queue worker / Solid Cable テーブルが本番で稼働している
- [ ] B6: 認証 E2E が CI で nightly green

## サブタスク一覧（PR 単位）

凡例: 🟢 単独着手可能 / 🟡 セット PR が望ましい / 🔴 他タスク完了待ち

### Phase 0（最優先・並列着手可能）
- 🟢 [B1: ActionCable Connection に JWT 認証を導入](./b1-cable-connection-jwt-auth.md)
- 🟢 [B2: Users#create を lazy provisioning に置き換え](./b2-users-lazy-provisioning.md)
- 🟢 [B3: CORS 方針決定と適用](./b3-cors-policy.md)

### Phase 1
- 🟢 [B4: AuthCore のデプロイと bank client 登録](./b4-authcore-deploy-and-client-registration.md)
- 🟡 [B5: 既存 CD への AUTHCORE_* 注入 / Solid Queue worker / ドキュメント更新](./b5-cd-env-injection-and-worker.md) — B1 / B2 とセット PR が望ましい

### Phase 2
- 🔴 [B6: 認証 E2E 疎通テスト](./b6-auth-e2e-smoke.md) — B1〜B5 完了後

## 関連ドキュメント

- アプリ側ロードマップ: `fuju-bank-app/docs/tasks/post-env-switch-roadmap.md`
- 既存: `prod-action-cable-solid-adapter-and-origins.md`（Phase -1 として完了済み）
