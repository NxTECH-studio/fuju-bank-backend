# README をドメイン概要中心に刷新し、消化済みの実装方針ドキュメントを整理する

## 概要

fuju-bank-backend のドメイン実装（User / Artifact / Account / Ledger / UserChannel）に加え、
AuthCore 連携（`external_user_id` / JWT 検証 / lazy プロビジョニング / introspection /
認証ポリシー適用）までが main 系統にマージされ実装済みとなった。
これに伴い `docs/tasks/` 配下の消化済み実装方針（`00-overview.md`, `01-` 〜 `20-`,
`21-` 〜 `25-`, `dedupe-test-ci-on-release-pr.md`）をすべて削除し、
README.md に「ドメイン概要 + 認証の要点」を自己完結した形で集約する。
README から `docs/tasks/` へのリンクは一切貼らない（もう残らないため）。

## 背景・目的

- `docs/tasks/00-overview.md` 〜 `20-broadcast-on-credit.md` は MVP 実装計画として使い切り、
  `21-` 〜 `25-` の AuthCore 連携も本日時点でマージ済み（最新コミット
  `48b9863 Merge pull request #45 from NxTECH-studio/feat/25-auth-policy-application`）。
  計画書がリポジトリのトップから見える「現在の姿」と二重管理になっており、
  歴史的記録は Git ログから復元可能なため、リポジトリ直下からは削除する。
- 現在の README.md は既に概要 / ドメイン / API / UserChannel / 技術スタック / セットアップ /
  開発コマンド等を含む形に刷新済みだが、以下を追補する必要がある:
  - 認証セクションが `docs/tasks/21-` 〜 `25-` への外部リンクで構成されており、削除後はリンク切れになる。
    21〜25 の要点（`external_user_id` / lazy プロビジョニング / JWT ローカル検証 /
    introspection 適用範囲 / MFA required concern）を README 内に要約して畳み込む。
  - 環境変数表が `DB_HOST` 系のみ。AuthCore 連携で実際に `config/initializers/authcore.rb`
    や `spec/rails_helper.rb` から参照されている `AUTHCORE_*` 系の変数が完全に欠落している
    ので、実運用で必要な変数をすべて列挙する。
  - 主要 API 表の認証列に「（AuthCore 適用予定）」のような暫定注記が残っているので
    現在の実装に合わせて更新する。
- 新規参画者・他層（マイニング層 / 参照 UI 層）の開発者が、README だけで
  「何のサービスで、どういうドメインで、どう叩くか、どう認証するか、どう動かすか」を
  理解できる状態にする。

## 影響範囲

- **変更対象**:
  - `README.md`（認証セクションを外部リンクから要約形式へ差し替え、環境変数表拡張、API 表の認証列更新）
  - `docs/tasks/` 配下の実装方針ドキュメント整理（削除のみ）
- **破壊的変更**: なし（ドキュメントのみ）
- **外部層（マイニング / SNS）への影響**: なし（コードは触らない）
- **コード影響**: なし

## スキーマ変更

なし。

## 削除するファイル

`docs/tasks/` 配下の以下 **27 ファイル全て** を `git rm` で削除する。
削除後、`docs/tasks/` 配下に残るのは本タスクの計画書である
`update-readme-with-domain-overview.md` のみ（本タスク完了後はこれも任意で削除可）。

### 全体設計ハブ（README に集約）

- `docs/tasks/00-overview.md`

### Phase 0: 基盤整備

- `docs/tasks/01-setup-api-error-handling.md`
- `docs/tasks/02-setup-schemafile-base.md`
- `docs/tasks/03-idempotency-concern.md`

### Phase 1: スキーマ定義

- `docs/tasks/04-add-users-table.md`
- `docs/tasks/05-add-artifacts-table.md`
- `docs/tasks/06-add-accounts-table.md`
- `docs/tasks/07-add-ledger-transactions-table.md`
- `docs/tasks/08-add-ledger-entries-table.md`

### Phase 2: モデル層

- `docs/tasks/09-user-model-and-account-bootstrap.md`
- `docs/tasks/10-artifact-model.md`

### Phase 3: サービス層（Ledger）

- `docs/tasks/11-ledger-service-mint.md`
- `docs/tasks/12-ledger-service-transfer.md`

### Phase 4: コントローラ層

- `docs/tasks/13-users-controller-create.md`
- `docs/tasks/14-users-controller-show-balance.md`
- `docs/tasks/15-artifacts-controller.md`
- `docs/tasks/16-mint-endpoint.md`
- `docs/tasks/17-transfer-endpoint.md`
- `docs/tasks/18-transactions-list-endpoint.md`

### Phase 5: リアルタイム配信

- `docs/tasks/19-user-channel-skeleton.md`
- `docs/tasks/20-broadcast-on-credit.md`

### Phase 6: AuthCore 連携（本タスクで削除対象に追加）

- `docs/tasks/21-add-external-user-id.md`
- `docs/tasks/22-jwt-auth-middleware.md`
- `docs/tasks/23-lazy-user-provisioning.md`
- `docs/tasks/24-authcore-introspection-client.md`
- `docs/tasks/25-auth-policy-application.md`

### CI 改善（消化済み）

- `docs/tasks/dedupe-test-ci-on-release-pr.md`

## 残すファイル

なし。AuthCore 連携（21〜25）も実装・マージ済みのため、21〜25 の要点は
README 内の「認証（AuthCore 連携）」セクションに要約して残す（外部リンクに頼らない）。

## README の更新方針

現 README は既に「プロジェクト概要 / 3 層アーキ / 主要ドメイン / 記帳モデル / 主要 API /
リアルタイム配信 / 認証 / 技術スタック / セットアップ / 開発コマンド / テスト / デプロイ /
参照」の章立てになっている。本タスクでは章立て自体は維持し、以下 3 点を更新する。

### 更新点 1: 「認証（AuthCore 連携）」セクションを要約形式に差し替え

現状は `docs/tasks/21-` 〜 `25-` への 5 本の外部リンクで構成されているため、
これを削除し、各タスクの要点を README 内に畳み込む。

新しいセクション案:

```markdown
## 認証（AuthCore 連携）

認証基盤は別リポジトリの **AuthCore**（JWT RS256 + introspection 併用）。
銀行側 `User` は AuthCore の `sub`（ULID, 26 文字）を `users.external_user_id` で同定します。

### 方針の要点

- **ユーザー同定**: `users.external_user_id`（NOT NULL, unique, limit 26）に AuthCore の `sub` を保存。
  `users.name` は lazy プロビジョニング時点では NULL 可（HUD からの後続 PATCH で埋める想定）。
- **JWT ローカル検証**: `Authorization: Bearer <jwt>` を `JwtAuthenticatable` concern で検証。
  署名（RS256, `AUTHCORE_JWT_PUBLIC_KEY`）、`exp`、`type=access`、`aud`、`iss` を確認し、
  `current_external_user_id` / `current_user` をコントローラに供給。
- **Lazy プロビジョニング**: JWT 検証成功時、`sub` に対応する `User` が無ければ
  `UserProvisioner` が `User` + `Account(kind: "user")` をその場で作成（`after_create` フック経由）。
  並行リクエストによる重複は `ActiveRecord::RecordNotUnique` rescue で吸収。
- **Introspection（金銭移動系のみ）**: `/ledger/mint` / `/ledger/transfer` には
  `IntrospectionRequired` concern を適用し、AuthCore の `POST /v1/auth/introspect` を毎回呼んで
  `active=true` を確認。revoke されたトークンは 401、AuthCore 不達は 503 + `AUTHCORE_UNAVAILABLE`。
- **MFA ゲート**: `MfaRequired` concern を用意済み。`introspection_result.mfa_verified` が
  偽のとき 403 + `MFA_REQUIRED`。適用対象は将来（高額 transfer 等）に拡張可能。

### 認証ポリシーの早見

| 種別 | ローカル JWT 検証 | Introspection | MFA |
|---|---|---|---|
| 参照系（`GET /users/:id`, `/users/:id/transactions`, `/artifacts/:id` 等） | 必須 | なし | なし |
| リソース作成（`POST /artifacts`） | 必須 | なし | なし |
| 金銭移動（`POST /ledger/mint`, `POST /ledger/transfer`） | 必須 | 必須 | `MfaRequired` include 箇所のみ |

### 追加エラーコード（認証系）

| `error.code` | HTTP | 用途 |
|---|---|---|
| `AUTHENTICATION_REQUIRED` | 401 | JWT 無効 / 欠落 |
| `TOKEN_INACTIVE` | 401 | introspection で `active=false`（revoke 済み） |
| `AUTHCORE_UNAVAILABLE` | 503 | AuthCore への問い合わせが 5xx / タイムアウト |
| `MFA_REQUIRED` | 403 | MFA 未検証トークンで `MfaRequired` 適用 action を叩いた |
```

> 備考: 上記テーブル列の正確な見出し（`error.code` 等）は既存 README の「統一エラーレスポンス」
> テーブルと揃える。上で挙げた認証系コードは **既存エラーコード表の直後に追記する**
> 形を推奨（重複の別テーブルではなく 1 つのテーブルを拡張してもよい）。

### 更新点 2: 環境変数表を AuthCore 系まで拡張

現 README の「セットアップ > 環境変数」表は DB_HOST / DB_USERNAME / DB_PASSWORD の 3 行のみ。
`config/initializers/authcore.rb` と `spec/rails_helper.rb` から実際に参照されている
変数を全て列挙して以下で置き換える:

| 変数名 | 用途 | Docker 時のデフォルト / 例 |
|---|---|---|
| `DB_HOST` | PostgreSQL ホスト | `db`（コンテナ名） |
| `DB_USERNAME` | PostgreSQL ユーザー名 | `fuju_bank_backend` |
| `DB_PASSWORD` | PostgreSQL パスワード | `password` |
| `AUTHCORE_JWT_PUBLIC_KEY` | AuthCore が発行する JWT の検証用公開鍵（PEM 文字列）。改行は `\n` エスケープで投入 | （secret 経由で注入） |
| `AUTHCORE_EXPECTED_ISSUER` | 許容する JWT の `iss` クレーム | `authcore` |
| `AUTHCORE_EXPECTED_AUDIENCE` | 許容する JWT の `aud` クレーム | `authcore` |
| `AUTHCORE_BASE_URL` | AuthCore のベース URL（introspection の呼び先） | `https://auth.fuju.example` |
| `AUTHCORE_CLIENT_ID` | introspection 呼び出し時の Basic 認証 client_id | （AuthCore から受領） |
| `AUTHCORE_CLIENT_SECRET` | introspection 呼び出し時の Basic 認証 client_secret | （AuthCore から受領, secret 経由で注入） |

表の直後に 1〜2 行の注記を添える:

> `AUTHCORE_JWT_PUBLIC_KEY` / `AUTHCORE_CLIENT_SECRET` は機密情報。Docker / Kamal では
> secret 経由で注入し、`.env` にコミットしないこと。テスト環境では `spec/rails_helper.rb` が
> `TestKeypair.public_key_pem` と固定値を自動注入するため、開発者側での設定は不要。

### 更新点 3: 主要 API 表の認証列を現行実装に合わせる

現 README の主要 API 表は `POST /users` の認証列が「（AuthCore 適用予定）」のままになっているが、
実装上 `/users` を新規作成する口は（lazy プロビジョニングに置き換わり）使わない方針。
認証列を以下のように整える:

| Method | Path | 用途 | 認証 |
|---|---|---|---|
| `GET` | `/users/:id` | User 情報 + 残高取得 | ローカル JWT |
| `GET` | `/users/:id/transactions` | 取引履歴（mint / transfer 統合） | ローカル JWT |
| `POST` | `/artifacts` | Artifact 作成 | ローカル JWT |
| `GET` | `/artifacts/:id` | Artifact 情報 | ローカル JWT |
| `POST` | `/ledger/mint` | 発行（マイニング層から） | ローカル JWT + introspection |
| `POST` | `/ledger/transfer` | 送金（User → User） | ローカル JWT + introspection |

> 補足 1 行: 「新規 `User` は認証済み JWT の初回リクエスト時に lazy プロビジョニングで
> 自動生成されるため、`POST /users` エンドポイントは提供しない。」

（※ `POST /users` 自体が実装済みで残っている場合は、README から削除せずに認証列を「ローカル JWT」
に更新する。`config/routes.rb` / `app/controllers/users_controller.rb` を事前確認してから決定する。
実装と不一致になる変更は避ける。）

## 実装ステップ

1. `develop` から `feat/update-readme-with-domain-overview` ブランチを切る
   （メモリ `feedback_feature_branch_required.md` に従い、develop 直コミット禁止）。
2. `config/routes.rb` と `app/controllers/users_controller.rb` を読み、`POST /users` が
   現行実装に存在するか確認（README の API 表をどう整えるかの判定に必要）。
3. `docs/tasks/` 配下の以下 27 ファイルを `git rm` で削除:
   - `00-overview.md`, `01-` 〜 `20-`（計 21 ファイル）
   - `21-` 〜 `25-`（計 5 ファイル）
   - `dedupe-test-ci-on-release-pr.md`
4. `README.md` を編集:
   - 「認証（AuthCore 連携）」セクションを、上記「更新点 1」の要約形式に置き換える
     （`docs/tasks/21-` 〜 `25-` への 5 本のリンクブロックを削除）。
   - 「統一エラーレスポンス」のエラーコード表に、認証系 4 コード
     （`AUTHENTICATION_REQUIRED` / `TOKEN_INACTIVE` / `AUTHCORE_UNAVAILABLE` / `MFA_REQUIRED`）を追記。
   - 「セットアップ > 環境変数」表を、上記「更新点 2」の 9 行構成に置き換える。
   - 「主要 API」表の認証列を、上記「更新点 3」のとおり現行実装に合わせて更新。
   - 主要ドメイン表の `User` 行にある「AuthCore 連携で `external_user_id` を追加予定
     （[task 21](./docs/tasks/21-add-external-user-id.md)）」を
     「AuthCore の `sub`（ULID）を `external_user_id` に保存（認証セクション参照）」に差し替え。
5. README 内の `docs/tasks/` を指す相対リンクが完全にゼロになっていることを `grep` で確認
   （削除漏れ防止）:
   ```bash
   grep -n "docs/tasks/" README.md   # 0 件になるべき
   ```
6. ローカルで README をプレビューし、表崩れと見出しレベル（H2/H3）が
   既存章立てと揃っていることを確認。
7. コミット → push → `develop` ベースで PR 作成（`/pr-creation` を想定）。

## テスト要件

- **リンク切れなし**: `grep -n "docs/tasks/" README.md` が 0 件。
- **削除確認**: `ls docs/tasks/` の結果が、本計画書
  （`update-readme-with-domain-overview.md`）のみ、または空であること。
- **環境変数網羅**: `config/initializers/authcore.rb` および `spec/rails_helper.rb` で
  `ENV.fetch` / `ENV[...]=` されている `AUTHCORE_*` が、README 環境変数表にすべて載っていること。
  確認コマンド:
  ```bash
  grep -E "ENV(\.fetch|\[)\s*\(?\"AUTHCORE_" config/initializers/authcore.rb spec/rails_helper.rb
  ```
- **API 表と実装の整合**: `config/routes.rb` に定義されているエンドポイントが、README の
  「主要 API」表と整合していること（特に `POST /users` の有無）。
- **認証エラーコードと実装の整合**: `app/errors/` 配下のエラークラスと README のエラーコード表が
  一致していること。
  ```bash
  ls app/errors/
  ```
  で `authcore_unavailable_error.rb` / `token_inactive_error.rb` /
  `mfa_required_error.rb` / `authentication_error.rb` の存在確認。
- **Markdown 構文**: 章番号・見出しレベル・表が崩れていないこと（プレビューで目視）。
- **コード影響なし**: `make rspec` / `make rubocop` は実行不要（ドキュメントのみ）。
  PR 上で CI が緑であることのみ確認。

## 技術的な補足

- 21〜25 の実装は既に main 系統にマージ済み（最新の関連コミット:
  `48b9863 Merge pull request #45 from NxTECH-studio/feat/25-auth-policy-application`,
  `c597b5f feat(auth): 金銭移動系に introspection / MFA required concern を追加`,
  `90b4bca Merge pull request #44 from NxTECH-studio/feat/24-authcore-introspection-client` 等）。
  計画書が残っていても実装と二重管理になるだけなので、README への要約吸収で十分。
- 歴史的記録（MVP 計画 00〜20 や 21〜25 の詳細）は必要になれば `git log --all -- docs/tasks/` や
  `git show <sha>:docs/tasks/XX.md` から復元可能なので、ドキュメントとしての保持は不要と判断。
- 21〜25 の要点 README 要約にあたり、`external_user_id` の `limit: 26` や
  `AUTHCORE_EXPECTED_*` のデフォルト値等の具体値は、削除前に
  `docs/tasks/21-` 〜 `25-` と `config/initializers/authcore.rb` から抽出済みの値を使う
  （本計画書の「更新点 1 / 2」に転記済み）。
- `POST /users` エンドポイントの扱いは実装の実態（`config/routes.rb`）を見てから決める。
  「lazy プロビジョニングに置き換わったので削除する」か「残して認証列のみ更新する」かは
  本計画書ではどちらも許容し、ステップ 2 の確認結果で分岐させる。
- `00-overview.md` の「非責務」リスト（手数料口座・SNS Webhook・日次突合ジョブ・CORS・
  alba シリアライザ等）や「依存グラフ」は README には持ち込まない。必要になった時点で
  `docs/architecture/` 等に切り出す方が望ましい。
