# Fuju Bank Backend

「感情を担保とする中央銀行」 fuju-bank の銀行層バックエンド。仮想通貨「ふじゅ〜」の
発行・記帳・決済・配信を司る Rails 8.1 API 専用アプリケーション。

鑑賞者がアート作品の前で滞留し・視線を向け「魂を削られた」時間を、ふじゅ〜として
ユーザーに還元する、というコンセプトを支える中央台帳です。

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
| **User** | ふじゅ〜の受け取り手。`name` / `public_key`（HUD 接続用、将来の署名検証）を保持。`after_create` で `Account(kind: "user")` が 1:1 で生える。AuthCore 連携で `external_user_id`（`sub` = ULID）を追加予定（[task 21](./docs/tasks/21-add-external-user-id.md)）。 |
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
| `POST` | `/users` | User 作成 | （AuthCore 適用予定） |
| `GET` | `/users/:id` | User 情報 + 残高取得 | ローカル JWT |
| `GET` | `/users/:id/transactions` | 取引履歴（mint / transfer 統合） | ローカル JWT |
| `POST` | `/artifacts` | Artifact 作成 | ローカル JWT |
| `GET` | `/artifacts/:id` | Artifact 情報 | ローカル JWT |
| `POST` | `/ledger/mint` | 発行（マイニング層から） | ローカル JWT + introspection |
| `POST` | `/ledger/transfer` | 送金（User → User） | ローカル JWT + introspection |

> 認証ポリシーの最終形は AuthCore 連携完了後に確定します。詳細は
> [認証（AuthCore 連携）](#認証authcore-連携)を参照。

### べき等性

`POST /ledger/mint` と `POST /ledger/transfer` は **`Idempotency-Key` ヘッダ
（または body の `idempotency_key`）必須**。`ledger_transactions.idempotency_key`
にユニーク制約があり、同一キーの重複受信は既存トランザクションをそのまま返します
（HTTP 200）。同一キーで payload が異なる場合は `409 IDEMPOTENCY_CONFLICT`。

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
| `VALIDATION_FAILED` | 422 | バリデーション失敗 |
| `NOT_FOUND` | 404 | リソース不在 |
| `INSUFFICIENT_BALANCE` | 422 | 送金時の残高不足 |
| `IDEMPOTENCY_CONFLICT` | 409 | 同一 `idempotency_key` で異なる payload |
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
銀行側 User は AuthCore の `sub`（ULID）を `external_user_id` で同定し、
lazy プロビジョニングで自動生成する方針です。

実装方針（進行中）:

- [docs/tasks/21-add-external-user-id.md](./docs/tasks/21-add-external-user-id.md) — `users.external_user_id` 追加 + `name` nullable 化
- [docs/tasks/22-jwt-auth-middleware.md](./docs/tasks/22-jwt-auth-middleware.md) — JWT 検証 concern（ローカル検証のみ）
- [docs/tasks/23-lazy-user-provisioning.md](./docs/tasks/23-lazy-user-provisioning.md) — lazy user プロビジョニング
- [docs/tasks/24-authcore-introspection-client.md](./docs/tasks/24-authcore-introspection-client.md) — AuthCore introspection クライアント
- [docs/tasks/25-auth-policy-application.md](./docs/tasks/25-auth-policy-application.md) — 認証ポリシー適用（参照系=ローカル / 金銭移動系=introspection）

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

| 変数名 | 説明 | Docker時のデフォルト |
|---|---|---|
| `DB_HOST` | PostgreSQL ホスト | `db`（コンテナ名） |
| `DB_USERNAME` | PostgreSQL ユーザー名 | `fuju_bank_backend` |
| `DB_PASSWORD` | PostgreSQL パスワード | `password` |

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

- **Kamal**（Docker ベース）。設定は `config/deploy.yml` と `Dockerfile`。
- **ブランチ戦略**: `develop` をデフォルトブランチとし、`feat/xxx` を `develop` から切って PR。
  `develop → main` のリリース PR は GitHub Actions で自動生成・更新されます。
- **本番ブランチ**: `main`（ブランチ保護あり、直接 push 禁止）。

## 開発フロー（Claude Code）

このプロジェクトでは Claude Code のカスタムコマンドを活用した開発フローを採用しています。

```
1. /create-task <やりたいこと>
   → エンジニアとの対話で実装方針ドキュメント（docs/tasks/）を作成。

2. /start-with-plan <方針ファイル>
   → 実装方針に沿ってコードを実装。

3. /code-review
   → 並列エージェントによるセルフレビュー（セキュリティ・設計・テスト・可読性・Lint）。

4. /pr-creation
   → PR 作成。

5. 人間がレビュー / マージ / QA / リリース
```

カスタムコマンドの定義は `.claude/commands/`、エージェント定義は `.claude/agents/` を
参照してください。進行中の実装方針ドキュメントは `docs/tasks/21-` 〜 `25-`（AuthCore 連携）
にあります。

## 参照

- `CLAUDE.md`: プロジェクトルール、Docker / Makefile / RuboCop 規約
- NxTECH Workspace: 「プロダクト落とし所 v5: 3層アーキテクチャ」設計思想
- [Ridgepole](https://github.com/ridgepole/ridgepole)
- [Solid Queue / Solid Cache / Solid Cable](https://github.com/rails/solid_queue)
