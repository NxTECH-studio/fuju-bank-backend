# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドです。

> **先に [README.md](./README.md) を読むこと。** プロジェクト概要 / 3 層アーキテクチャ /
> ドメイン / 記帳モデル / API / 認証 / セットアップ / Makefile 一覧 / デプロイは
> README.md が一次ソース。本ファイルは Claude Code 向けの規約と実装ナビに集中する。

## よく使うコマンド

開発環境は Docker（`compose.yml`）で構築し、Makefile 経由で実行する。
詳細な一覧は [README.md の「開発コマンド（Makefile）」](./README.md#開発コマンドmakefile) を参照。
Claude が頻繁に使うのは以下:

```bash
make rspec                                   # 全テスト実行
make rspec ARGS=spec/models/                 # ディレクトリ単位
make rspec ARGS=spec/models/user_spec.rb     # ファイル単位
make rspec ARGS=spec/models/user_spec.rb:42  # 行番号指定
make rubocop                                 # 全 lint
make rubocop/fix                             # 安全な自動修正
make db/schema/apply                         # Ridgepole スキーマ適用（dev + test）
```

## ブランチ戦略

詳細は [README.md の「デプロイ」](./README.md#デプロイ) 参照。
Claude は `develop` から `feat/xxx` を切って `develop` へ PR を出す。
`main` への直接 push は禁止（リリース PR は GitHub Actions が自動生成）。

## アーキテクチャ

### 全体像

README の [3 層アーキテクチャでの位置づけ](./README.md#3-層アーキテクチャでの位置づけ) /
[主要ドメイン](./README.md#主要ドメイン) / [記帳モデル](./README.md#記帳モデル複式簿記) を参照。
本リポジトリは **API 専用**（`config.api_only = true`、ビュー / アセットなし）。

### ディレクトリ構成（実装時のナビ）

#### app/controllers/

- `application_controller.rb` — ベース。`JwtAuthenticatable` を全 action に適用。
  `current_external_user_id` / `current_user` ヘルパを供給。
- `concerns/jwt_authenticatable.rb` — `Authorization: Bearer` の RS256 ローカル検証。
  `service_actor_allowed!` を宣言したコントローラは `type=service` も受理し、
  `current_actor_type` で actor 種別を区別できる。
- `concerns/introspection_required.rb` — AuthCore `/v1/auth/introspect` を毎回叩く。
  金銭移動系（`LedgerController`）のみ include。
- `concerns/mfa_required.rb` — `introspection_result.mfa_verified?` を要求。未適用箇所あり。
- `concerns/idempotent.rb` — `Idempotency-Key` ヘッダの取り回し。
- `concerns/error_responder.rb` — 統一エラーレスポンス（`error.code` / `error.message`）。
- `users_controller.rb` / `user_transactions_controller.rb` / `artifacts_controller.rb` /
  `ledger_controller.rb` — リソース別エンドポイント。

#### app/models/

- `user.rb` — `external_user_id`（AuthCore の `sub`、ULID 26 文字）で同定。
  `after_create` で `Account(kind: "user")` を 1:1 で生成。
- `artifact.rb` — `location_kind` enum (`physical` / `url`)。
- `account.rb` — `kind` enum で `system_issuance` / `user` / `store` を区別。
  `balance_fuju` は `ledger_entries.amount` の SUM キャッシュ。
- `ledger_transaction.rb` — `kind` (`mint` / `transfer`) / `idempotency_key` (unique) /
  `metadata` JSONB。`SUM(entries.amount) = 0` を validation で保証。
- `ledger_entry.rb` — 複式簿記の片側。1 トランザクションに必ず 2 行以上。
- `store.rb` — QR 決済基盤（MPM）用の店舗エンティティ
  （`docs/tasks/qr-payment-foundation-mpm/` 参照）。

#### app/services/

- `ledger/mint.rb` — Artifact → User の発行サービス。
  `ActiveRecord::Base.transaction` で原子性を担保し、成功時に `Ledger::Notifier` を呼ぶ。
- `ledger/transfer.rb` — User → User の送金サービス。残高不足は `INSUFFICIENT_BALANCE`。
- `ledger/notifier.rb` — `UserChannel` への broadcast を担当。
- `user_provisioner.rb` — JWT 検証成功時に `sub` から User + Account を lazy 作成。
  `ActiveRecord::RecordNotUnique` を rescue して並行リクエストを吸収。
- `authcore/jwt_verifier.rb` — RS256 / `aud` / `iss` / `exp` / `type` を検証する責務。
  Connection / Controller 双方から使う。
- `authcore/introspection_client.rb` — AuthCore `/v1/auth/introspect` のクライアント。
  RFC 7662 準拠（Basic Auth + form）。
- `authcore/introspection_result.rb` — introspection レスポンスの値オブジェクト
  (`active?` / `mfa_verified?` / `scope` 等)。

#### app/channels/

- `application_cable/connection.rb` — JWT 認証を Connection レイヤで実施
  （subprotocol `Sec-WebSocket-Protocol: bearer, <jwt>`）。
- `application_cable/channel.rb` — ベース。
- `user_channel.rb` — 受け手 User へ `credit` イベントを broadcast。
  `current_user` に対して `stream_for` する形が安全。

#### app/jobs/

現状は `application_job.rb` のみ。Solid Queue で `bin/jobs` または compose の `worker`
が消化する想定（必要に応じて追加）。

### 主要な不変条件（実装時に壊さない）

| 制約 | 実装場所 |
|---|---|
| `SUM(ledger_entries.amount) = 0` per transaction | `LedgerTransaction` の validation |
| `accounts.balance_fuju >= 0 WHERE kind = 'user'` | DB の CHECK 制約（部分制約） |
| `ledger_transactions.idempotency_key` unique | DB のユニーク制約 |
| mint / transfer 処理の原子性 | `ActiveRecord::Base.transaction` で囲む |
| 受取人の cross-service 同定 | `users.external_user_id` (= AuthCore の `sub`) で行う |

### スキーマ管理

Rails マイグレーションではなく [Ridgepole](https://github.com/ridgepole/ridgepole) を使用。
テーブル定義は `db/Schemafile` に直書き or サブファイル require。
**Claude が新規タスクで「migration を作る」ことを提案してはいけない**。
`db/Schemafile` を編集し、`make db/schema/apply` で dev / test に適用する。

### バックグラウンド / Cache / Cable

- Solid Queue（Active Job アダプタ）/ Solid Cache（`Rails.cache` アダプタ）/
  Solid Cable（ActionCable アダプタ）。すべて DB ベースで Redis 不要。
- production の Cable adapter / `allowed_request_origins` / hosts は
  `docs/tasks/prod-action-cable-solid-adapter-and-origins.md` に経緯あり。

### CORS

ネイティブクライアントのみ運用のため CORS 設定不要。
`config/initializers/cors.rb` は無効化済みで、`rack-cors` Gem も導入していない。
ブラウザクライアントから叩く要件が出たら `docs/tasks/b3-cors-policy.md` の
選択肢 (b) に従って `rack-cors` を再導入する。

### デプロイ

GitHub Actions (`.github/workflows/cd.yml`) が `main` push 時に Tailscale + SSH で
Proxmox CT に入り、`docker compose -p fuju-bank-prod -f compose.prod.yml up -d --build`
を実行。本番イメージは `Dockerfile.prod`。詳細は
[README.md の「デプロイ」](./README.md#デプロイ) 参照。

## コードスタイル (RuboCop)

デフォルトと異なる主要ルール:

- **文字列**: ダブルクォート（`"hello"`）。例外: Gemfile。
- **Hash ショートハンド**: 禁止 — 常に `key: value` を使い、`key:` 省略記法は使わない
  （`Style/HashSyntax: never`）。
- **末尾カンマ**: 複数行の引数・配列・ハッシュでは必須。
- **モジュールスタイル**: コンパクト形式（`class Foo::Bar`、ネストしない）。
- **行の長さ**: 最大 160 文字（spec ファイルは制限なし）。
- **Lambda 記法**: リテラル（`-> { }`、`lambda { }` は使わない）。
- **`let` vs `let!`（RSpec）**: カスタム cop `RSpec/PreferLetBang` が有効 — `let!` を優先。
- **ドキュメント**: モデル・ジョブ・サービスにはクラスコメント必須（基底クラスは除く）。
- **述語メソッドの接頭辞**: `is_` は禁止（`is_active?` ではなく `active?`）。

## テスト

- RSpec + FactoryBot（`create`, `build` 等はメソッドとして直接利用可能）。
- `database_rewinder` で DB クリーンアップ。
- `TimeHelpers` 組み込み済み — `travel_to`, `freeze_time` 等が使える。
- `bullet` / `simplecov` / `test-prof` は Gemfile に同梱しているが現状は未設定。
  必要時に各自セットアップする。

## docs/tasks の使い方

`docs/tasks/` 配下に実装方針ドキュメントを置き、`/start-with-plan {ファイル名}` で
実装に取り掛かれる粒度で管理する。タスクの一覧とステータスは
[`docs/tasks/INDEX.md`](./docs/tasks/INDEX.md) で一元管理する
（タスクファイル本体にはステータスを書き込まない）。
