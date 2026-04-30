# Fuju Bank Backend

「感情を担保とする中央銀行」 fuju-bank の銀行層バックエンド。仮想通貨「ふじゅ〜」の
発行・記帳・決済・配信を司る Rails 8.1 API 専用アプリケーション。

鑑賞者がアート作品の前で滞留し・視線を向けた時間を、作品に「魂を削った」作家（User）へ
ふじゅ〜として還元する、というコンセプトを支える中央台帳です。

## 3 層アーキテクチャでの位置づけ

本リポジトリは fuju-bank プロダクトの **1 層目（銀行層）** であり、他の 2 層から
呼び出される **受け身のサービス** です。

| 層 | 責務 |
|---|---|
| 1 層目（本リポジトリ）**銀行** | 発行・記帳・決済・配信の中央台帳 |
| 2 層目 **マイニング** | ブラウザ内 MediaPipe で視線・滞留をエッジ解析、重み付け計算 |
| 3 層目 **デモ SNS / 作家 HUD** | タイムライン滞留でマイニング、作家 HUD へ push 通知 |

小数点の重み付け計算はマイニング層が担い、切り捨てた **整数値** だけが銀行に渡ります。
銀行内部は小数を扱いません（ふじゅ〜の単位は `bigint`）。

## 主要ドメイン

| エンティティ | 役割 |
|---|---|
| **User** | ふじゅ〜の受け取り手。`name` / `public_key`（HUD 接続用、将来の署名検証）を保持。`after_create` で `Account(kind: "user")` が 1:1 で生える。AuthCore の `sub`（ULID）を `external_user_id` に保存（認証セクション参照）。 |
| **Artifact** | 発行（mint）の起点。物理場所または URL に紐付く。`location_kind` enum (`physical` / `url`)。 |
| **Account** | 勘定口座。`kind` enum で `system_issuance`（発行源、マイナス残高 OK、`user_id` NULL）と `user`（マイナス残高禁止、CHECK 制約）を区別。`balance_fuju` は `ledger_entries.amount` の SUM キャッシュ。 |
| **LedgerTransaction** | 1 回の記帳イベント。`kind`（`mint` / `transfer`）、`idempotency_key`（ユニーク）、`metadata` JSONB（滞留秒数 / 視線強度 等）、`occurred_at`（クライアント時刻）。 |
| **LedgerEntry** | 明細。1 トランザクションに **必ず 2 行以上**、`SUM(amount) = 0` をモデル層で保証する複式簿記の片側。 |

## 記帳モデル（複式簿記）

「PayPay と銀行口座のハイブリッド + 仮想通貨」という立ち位置を素直に表現するため、
**複式簿記（entries テーブル）** を採用しています。

### 仕訳パターン

```
mint (Artifact → User):
  system_issuance: -N   (発行口から出る)
  user A:          +N   (受け手に入る)

transfer (User → User):
  user A: -N            (送り手から出る)
  user B: +N            (受け手に入る)
```

### 不変条件

| 制約 | 実装場所 |
|---|---|
| `SUM(entries.amount) = 0` per transaction | `LedgerTransaction` モデル層 validation |
| `accounts.balance_fuju >= 0 WHERE kind = 'user'` | DB の CHECK 制約（部分制約） |
| `ledger_transactions.idempotency_key` unique | DB のユニーク制約 |
| mint / transfer 処理の原子性 | `ActiveRecord::Base.transaction` で囲む |

## 主要 API

| Method | Path | 用途 | 認証 |
|---|---|---|---|
| `POST` | `/users` | User 作成 | ローカル JWT |
| `GET` | `/users/:id` | User 情報 + 残高取得 | ローカル JWT |
| `GET` | `/users/:id/transactions` | 取引履歴（mint / transfer 統合） | ローカル JWT |
| `POST` | `/artifacts` | Artifact 作成 | ローカル JWT |
| `GET` | `/artifacts/:id` | Artifact 情報 | ローカル JWT |
| `POST` | `/ledger/mint` | 発行（マイニング層から） | ローカル JWT + introspection（service token は `mint:creator_payouts` scope 必須） |
| `POST` | `/ledger/transfer` | 送金（User → User） | ローカル JWT + introspection |

> 認証ポリシーの詳細は [認証（AuthCore 連携）](#認証authcore-連携) を参照。

### べき等性

`POST /ledger/mint` と `POST /ledger/transfer` は **`Idempotency-Key` ヘッダ
（または body の `idempotency_key`）必須**。`ledger_transactions.idempotency_key`
にユニーク制約があり、同一キーの重複受信は既存トランザクションをそのまま返します
（HTTP 200）。

### 統一エラーレスポンス

```json
{
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "残高が不足しています"
  }
}
```

| `error.code` | HTTP | 用途 |
|---|---|---|
| `VALIDATION_FAILED` | 400 | バリデーション失敗 |
| `NOT_FOUND` | 404 | リソース不在 |
| `INSUFFICIENT_BALANCE` | 422 | 送金時の残高不足 |
| `UNAUTHENTICATED` | 401 | JWT 無効 / 欠落 |
| `TOKEN_INACTIVE` | 401 | introspection で `active=false`（revoke 済み） |
| `AUTHCORE_UNAVAILABLE` | 503 | AuthCore への問い合わせが 5xx / タイムアウト |
| `MFA_REQUIRED` | 403 | MFA 未検証トークンで `MfaRequired` 適用 action を叩いた |
| `FORBIDDEN` | 403 | scope 不足（service token が必要 scope を持たない 等） |
| `INTERNAL_ERROR` | 500 | 想定外エラー |

## リアルタイム配信（ActionCable / UserChannel）

`UserChannel` は受け手 User に対して `credit` イベントを broadcast します。
作家 HUD 等のクライアントは `user_id` を subscribe params で渡してチャネルに接続します
（MVP は簡易、将来 `public_key` 署名検証を追加予定）。

### broadcast ペイロード例

```json
{
  "type": "credit",
  "amount": 15,
  "transaction_id": 42,
  "transaction_kind": "mint",
  "artifact_id": 7,
  "from_user_id": null,
  "metadata": { "dwell_seconds": 12, "gaze_strength": 0.8 },
  "occurred_at": "2026-04-18T12:34:56Z"
}
```

`Ledger::Mint` / `Ledger::Transfer` サービスが成功すると、`Ledger::Notifier` が
受け手 User の Channel に上記ペイロードを push します。

## 認証（AuthCore 連携）

認証基盤は別リポジトリの **AuthCore**（JWT RS256 + introspection 併用）。
銀行側 `User` は AuthCore の `sub`（ULID, 26 文字）を `users.external_user_id` で同定します。

### 方針の要点

- **ユーザー同定**: `users.external_user_id`（NOT NULL, unique, limit 26）に AuthCore の `sub` を保存。
  `users.name` は lazy プロビジョニング時点では NULL 可（HUD からの後続 PATCH で埋める想定）。
- **JWT ローカル検証**: `Authorization: Bearer <jwt>` を `JwtAuthenticatable` concern で検証。
  署名（RS256, `AUTHCORE_JWT_PUBLIC_KEY`）、`exp`、`type=access`、`aud`、`iss` を確認し、
  `current_external_user_id` / `current_user` をコントローラに供給します。
  クラスレベルで `service_actor_allowed!` を宣言したコントローラは追加で `type=service`
  も受理し、`current_actor_type` で actor 種別を区別できます（`LedgerController#mint`
  が代理 mint のために有効化）。
- **Lazy プロビジョニング**: JWT 検証成功時、`sub` に対応する `User` が無ければ
  `UserProvisioner` が `User` + `Account(kind: "user")` をその場で作成します（`after_create` フック経由）。
  並行リクエストによる重複は `ActiveRecord::RecordNotUnique` rescue で吸収します。
- **Introspection（金銭移動系のみ）**: `POST /ledger/mint` / `POST /ledger/transfer` には
  `IntrospectionRequired` concern を適用し、AuthCore の `POST /v1/auth/introspect` を毎回呼んで
  `active=true` を確認します。revoke 済みトークンは 401、AuthCore 不達は 503 + `AUTHCORE_UNAVAILABLE`。
- **Scope ベースの代理 mint authz**: `POST /ledger/mint` を service token で呼ぶ場合、
  AuthCore introspect の `scope` クレームに `mint:creator_payouts` を含むことを要求します。
  scope 不足は 403 `FORBIDDEN`。ユーザートークン経路（既存 MVP）には scope 検査は
  かかりません。fuju-emotion-model などの上位サービスは AuthCore の `clients.allowed_scope`
  に当該 scope を登録した上で `POST /oauth/token` から service token を取得して呼びます。
- **mint 受取人 ID の cross-service 一致保証**: `POST /ledger/mint` の `user_id`
  パラメータは **AuthCore の `sub`（= `users.external_user_id`、ULID 26 文字）** を
  期待します。Bank 内部の autoincrement PK (`users.id`) は受け付けません。これにより
  SNS の作者 ID（= AuthCore sub）と Bank の受取口座が cross-service で一意に対応
  することが保証されます。Bank に該当 User が未登録なら `UserProvisioner` で
  lazy 作成されるため、creator がまだ Bank HUD にログインしていなくても代理 mint
  が成立します。`artifact_id` は任意で、未指定時は `ledger_transactions.artifact_id`
  は NULL のまま記帳します（content_id 等の追跡情報は metadata JSONB に乗せる）。
- **MFA ゲート**: `MfaRequired` concern を用意済み。`introspection_result.mfa_verified` が
  偽のとき 403 + `MFA_REQUIRED`。適用対象は将来（高額 transfer 等）に拡張可能。

### 認証ポリシー早見表

| 種別 | ローカル JWT 検証 | Introspection | MFA |
|---|---|---|---|
| 参照系（`GET /users/:id`, `/users/:id/transactions`, `GET /artifacts/:id`） | 必須 | なし | なし |
| リソース作成（`POST /users`, `POST /artifacts`） | 必須 | なし | なし |
| 金銭移動（`POST /ledger/mint`, `POST /ledger/transfer`） | 必須 | 必須 | `MfaRequired` include 箇所のみ |

## 技術スタック

| カテゴリ | 技術 |
|---|---|
| 言語 | Ruby 4.0.2 |
| フレームワーク | Rails 8.1 (API only) |
| DB | PostgreSQL |
| スキーマ管理 | Ridgepole |
| バックグラウンドジョブ | Solid Queue |
| キャッシュ | Solid Cache |
| リアルタイム配信 | Solid Cable / ActionCable |
| デプロイ | Kamal (Docker) |
| テスト | RSpec, FactoryBot, database_rewinder, bullet |
| Lint | RuboCop |
| セキュリティ | Brakeman, bundler-audit |

## セットアップ

### Docker（推奨）

PostgreSQL を含めたすべての依存をコンテナ内で完結させます。

```bash
# 初回セットアップ（ビルド → 起動 → DB作成 → スキーマ適用）
make setup

# 2回目以降の起動
make up

# 停止
make down
```

> **前提条件**: Docker と Docker Compose がインストールされていること。

### ローカル直接セットアップ

Docker を使わない場合は、PostgreSQL をローカルにインストールした上で以下を実行してください。

```bash
bundle install
bin/rails db:create
bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile
bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile
bin/rails server
```

### 環境変数

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
| `AUTHCORE_CLIENT_SECRET` | introspection 呼び出し時の Basic 認証 client_secret | （AuthCore から受領、secret 経由で注入） |

> `AUTHCORE_JWT_PUBLIC_KEY` / `AUTHCORE_CLIENT_SECRET` は機密情報。Docker / Kamal では
> secret 経由で注入し、`.env` にコミットしないこと。テスト環境では `spec/rails_helper.rb` が
> `TestKeypair.public_key_pem` と固定値を自動注入するため、開発者側での設定は不要。

## 開発コマンド（Makefile）

`make help` で一覧を確認できます。主要なコマンド:

```bash
# Docker
make build            # イメージビルド
make up               # コンテナ起動
make down             # コンテナ停止
make restart          # コンテナ再起動
make logs             # ログ表示
make ps               # コンテナ状態

# Setup / DB
make setup            # 初回セットアップ（build → up → bundle → db:create → ridgepole apply x2）
make db/create        # DB 作成
make db/schema/apply  # Ridgepole スキーマ適用（dev + test）
make db/reset         # DB drop → create → schema apply

# Rails
make console          # Rails コンソール
make bundle           # bundle install
make sh               # web コンテナに bash でアタッチ

# Test / Lint / Security
make rspec            # テスト実行（make rspec ARGS=spec/path で絞り込み可）
make rubocop          # RuboCop チェック
make rubocop/fix      # RuboCop 安全な自動修正（rubocop -a）
make rubocop/fix-all  # RuboCop 全自動修正（rubocop -A、unsafe 含む）
make brakeman         # セキュリティ解析
make bundler-audit    # Gem 脆弱性スキャン

# Cleanup
make clean            # docker compose down -v
```

Docker を使わない場合の直接コマンド:

```bash
bundle exec rspec
bundle exec rubocop
bin/brakeman --no-pager
bin/bundler-audit
bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile
bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile
```

## テスト / Lint / セキュリティ

- **RSpec + FactoryBot**: `database_rewinder` で各テスト後にクリーン、`bullet` で N+1 検出、
  `test-prof` でプロファイリング、SimpleCov は CI のみ有効。
- **`let!` を常用**: プロジェクトのカスタム cop `RSpec/PreferLetBang` が有効で、
  スカラー値や遅延評価目的でも `let!` で統一します（詳細は `CLAUDE.md`）。
- **RuboCop**: ダブルクォート / `key: value` ハッシュ / 末尾カンマ / コンパクトモジュール定義 /
  最大 160 文字 / Lambda リテラル等。詳細は `CLAUDE.md` の「コードスタイル」を参照。
- **Brakeman / bundler-audit**: PR 時に確認します。

## デプロイ

- **Kamal**（Docker ベース）。設定は `config/deploy.yml` と `Dockerfile.prod`（本番イメージ用）。
- **ブランチ戦略**: `develop` をデフォルトブランチとし、`feat/xxx` を `develop` から切って PR。
  `develop → main` のリリース PR は GitHub Actions で自動生成・更新されます。
- **本番ブランチ**: `main`（ブランチ保護あり、直接 push 禁止）。

## 参照

- `CLAUDE.md`: プロジェクトルール、Docker / Makefile / RuboCop 規約
- NxTECH Workspace: 「プロダクト落とし所 v5: 3層アーキテクチャ」設計思想
- [Ridgepole](https://github.com/ridgepole/ridgepole)
- [Solid Queue / Solid Cache / Solid Cable](https://github.com/rails/solid_queue)
