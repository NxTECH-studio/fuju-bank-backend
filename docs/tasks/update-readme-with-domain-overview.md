# README をドメイン概要中心に刷新し、消化済みの実装方針ドキュメントを整理する

## 概要

fuju-bank-backend のドメイン実装（User / Artifact / Account / Ledger / UserChannel まで）が
一巡したので、`docs/tasks/` 配下の消化済み実装方針（00, 01〜20, dedupe-...）を削除し、
代わりに `00-overview.md` の内容を README.md にドメイン概要として集約する。
AuthCore 連携（21〜25）はまだ進行中なので残し、README からはリンクで参照する。

## 背景・目的

- `docs/tasks/00-overview.md` 〜 `20-broadcast-on-credit.md` までは MVP 実装計画として
  使い切ったため、リポジトリのトップから見える「現在の姿」と乖離している。
- 現在の README.md は Rails テンプレ寄りで、fuju-bank が「感情を担保とする中央銀行」で
  あることや、3 層アーキの 1 層目（銀行層）であること、ドメイン構造（複式簿記 / mint /
  transfer / UserChannel broadcast）に一切触れていない。
- 新規参画者・他層（マイニング層 / 参照 UI 層）の開発者が、まず README を読んで
  「何のサービスで、どういうドメインで、どう叩くか」を理解できる状態にしたい。
- AuthCore 連携（21〜25）はまだ実装中のため、実装方針として残しつつ、README からは
  リンクで導線を作る。

## 影響範囲

- **変更対象**:
  - `README.md`（全面書き直し）
  - `docs/tasks/` 配下の実装方針ドキュメント整理（削除のみ。21〜25 は不変）
- **破壊的変更**: なし（ドキュメントのみ）
- **外部層（マイニング / SNS）への影響**: なし（コードは触らない。ただし README が
  外部層からの参照ドキュメントとしても機能するようになる）
- **コード影響**: なし

## スキーマ変更

なし。

## 削除するファイル

`docs/tasks/` 配下の以下を削除する（27 ファイル中 22 ファイル）。

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

### CI 改善（消化済み）

- `docs/tasks/dedupe-test-ci-on-release-pr.md`

## 残すファイル

AuthCore 連携は進行中につき残す。README からはリンクで導線を作る。

- `docs/tasks/21-add-external-user-id.md` — users.external_user_id 追加 + name nullable 化
- `docs/tasks/22-jwt-auth-middleware.md` — JWT 検証 concern（ローカル検証のみ）
- `docs/tasks/23-lazy-user-provisioning.md` — lazy user プロビジョニング
- `docs/tasks/24-authcore-introspection-client.md` — AuthCore introspection クライアント
- `docs/tasks/25-auth-policy-application.md` — 認証ポリシー適用（参照系=ローカル / 金銭移動系=introspection）

## 新 README の章立て案

想定読者は **ハイブリッド（C）**: 冒頭 1〜2 セクションは外部層開発者・新規参加者向けの
コンセプト紹介、それ以降は内部開発者向けの実用情報。ER 図は載せない。
make コマンドはフル一覧を README に置く（CLAUDE.md と重複しても自己完結を優先）。

### 1. プロジェクト概要

- 「fuju-bank は感情を担保とする中央銀行」「ふじゅ〜という仮想通貨を発行・記帳・決済・配信する」
  の 1〜2 段落。
- 鑑賞者がアート作品の前で滞留して魂を削られた時間を、ふじゅ〜として還元する、
  というコンセプト導入。

### 2. 3 層アーキテクチャでの位置づけ

`00-overview.md` 1.2 節をベースに、本リポジトリが **1 層目（銀行）** であり、
2 層目（マイニング）、3 層目（参照 UI / 作家 HUD）から呼び出される受け身のサービス
であることを表で示す。

| 層 | 責務 |
|---|---|
| 1 層目（本リポジトリ）銀行 | 発行・記帳・決済・配信の中央台帳 |
| 2 層目 マイニング | ブラウザ内 MediaPipe で視線・滞留をエッジ解析、重み付け計算 |
| 3 層目 デモ SNS / 作家 HUD | タイムライン滞留でマイニング、作家 HUD へ push 通知 |

「小数の重み付けはマイニング層、銀行は整数のみ扱う」も 1 行で添える。

### 3. 主要ドメイン（テキストで簡潔に）

ER 図は載せず、各エンティティを 2〜3 行で要約。

- **User** — ふじゅ〜の受け取り手。`name` / `public_key`（HUD 接続用、将来の署名検証）/
  `external_user_id`（AuthCore の sub = ULID, 21 で追加）。`after_create` で
  `Account(kind: "user")` が 1:1 で生える。
- **Artifact** — 発行（mint）の起点。物理場所または URL に紐付く。`location_kind` enum
  （`physical` / `url`）。
- **Account** — 勘定口座。`kind` enum で `system_issuance`（発行源、マイナス残高 OK、
  `user_id` NULL）と `user`（マイナス残高禁止、CHECK 制約）を区別。`balance_fuju` は
  `ledger_entries.amount` の SUM キャッシュ。
- **LedgerTransaction** — 1 回の記帳イベント。`kind`（`mint` / `transfer`）、
  `idempotency_key`（ユニーク）、`metadata` JSONB（滞留秒数 / 視線強度等）、
  `occurred_at`（クライアント時刻）。
- **LedgerEntry** — 明細。1 トランザクションに **必ず 2 行以上**、`SUM(amount) = 0`
  をモデル層で保証する複式簿記。

### 4. 記帳モデル（複式簿記、要点のみ）

`00-overview.md` 4 章を圧縮して、mint / transfer の仕訳パターンを各 5〜6 行で紹介。

```
mint:     system_issuance: -N / user A: +N
transfer: user A: -N / user B: +N
```

不変条件 4 つ（`SUM=0` / `balance_fuju >= 0` / `idempotency_key` unique /
`ActiveRecord::Base.transaction` で原子性）も箇条書きで残す。

### 5. 主要 API（エンドポイント早見）

`00-overview.md` 5.1 を踏襲。認証列は「ローカル JWT」「ローカル JWT + introspection」
の 2 値で書く（25 適用後の状態を示す。実装途上であれば「適用予定」と注記）。

| Method | Path | 用途 | 認証 |
|---|---|---|---|
| `POST` | `/users` | User 作成 | （TODO） |
| `GET` | `/users/:id` | User 情報 + 残高取得 | ローカル JWT |
| `GET` | `/users/:id/transactions` | 取引履歴 | ローカル JWT |
| `POST` | `/artifacts` | Artifact 作成 | ローカル JWT |
| `GET` | `/artifacts/:id` | Artifact 情報 | ローカル JWT |
| `POST` | `/ledger/mint` | 発行（マイニング層から） | ローカル JWT + introspection |
| `POST` | `/ledger/transfer` | 送金（User → User） | ローカル JWT + introspection |

`Idempotency-Key` ヘッダ（`/ledger/mint`, `/ledger/transfer` 必須）と統一エラー
レスポンス形式（`{ "error": { "code": ..., "message": ... } }`）を 1 段落で説明。
エラーコード表（`VALIDATION_FAILED` / `NOT_FOUND` / `INSUFFICIENT_BALANCE` /
`IDEMPOTENCY_CONFLICT` / `INTERNAL_ERROR`）も載せる。

### 6. リアルタイム配信（ActionCable / UserChannel）

- `UserChannel` は受け手 User に対して `credit` イベントを broadcast する。
- subscribe は `user_id` パラメータで identify（MVP 簡易、将来 `public_key` 署名検証）。
- ペイロードのサンプル（`type: "credit"`, `amount`, `transaction_id`,
  `transaction_kind`, `artifact_id`, `from_user_id`, `metadata`）を 1 ブロック貼る。
- broadcast フックは `Ledger::Mint` / `Ledger::Transfer` 成功後（`Ledger::Notifier`
  で実装済み、commit `fd5bbd4` 参照）。

### 7. 認証（AuthCore 連携）

- 認証基盤は別リポジトリの **AuthCore**（JWT RS256 + introspection 併用）。
- 銀行側 User は AuthCore の `sub`（ULID）を `external_user_id` で同定し、
  lazy プロビジョニングで自動生成する方針。
- 詳細・実装方針は以下を参照（実装進行中）:
  - [docs/tasks/21-add-external-user-id.md](./docs/tasks/21-add-external-user-id.md)
  - [docs/tasks/22-jwt-auth-middleware.md](./docs/tasks/22-jwt-auth-middleware.md)
  - [docs/tasks/23-lazy-user-provisioning.md](./docs/tasks/23-lazy-user-provisioning.md)
  - [docs/tasks/24-authcore-introspection-client.md](./docs/tasks/24-authcore-introspection-client.md)
  - [docs/tasks/25-auth-policy-application.md](./docs/tasks/25-auth-policy-application.md)

### 8. 技術スタック

既存 README の表を踏襲。Solid Cable / ActionCable / Ruby 4.0.2 を追記。

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

### 9. セットアップ

既存 README を踏襲。

- Docker（推奨）: `make setup` → `make up`
- ローカル直接: `bundle install` → `bin/rails db:create` → `ridgepole ... --apply`
- 環境変数表（`DB_HOST` / `DB_USERNAME` / `DB_PASSWORD`）

### 10. 開発コマンド（Makefile フル一覧）

CLAUDE.md と重複してでも自己完結させる方針。Makefile から取得した実コマンドを並べる。

```bash
# Docker
make build / make up / make down / make restart / make logs / make ps

# Setup / DB
make setup            # 初回（build → up → bundle → db:create → ridgepole apply x2）
make db/create
make db/schema/apply  # Ridgepole スキーマ適用（dev + test）
make db/reset         # DB drop → create → schema apply

# Rails
make console
make bundle
make sh               # web コンテナに bash でアタッチ

# Test / Lint / Security
make rspec [ARGS=spec/path]
make rubocop
make rubocop/fix         # rubocop -a（safe）
make rubocop/fix-all     # rubocop -A（unsafe 含む）
make brakeman
make bundler-audit

# Cleanup
make clean            # docker compose down -v

# Help
make help
```

Docker を使わない場合の直接コマンド（`bundle exec rspec`, `bundle exec rubocop`,
`bin/brakeman --no-pager`, `bin/bundler-audit`, `bundle exec ridgepole ...`）も
既存 README どおり残す。

### 11. テスト / Lint / セキュリティ

- RSpec + FactoryBot、`database_rewinder` でクリーン、`bullet` で N+1 検出、
  `test-prof` でプロファイリング、SimpleCov（CI のみ）。
- `let!` を常用（`RSpec/PreferLetBang` 強制、CLAUDE.md 参照）。
- RuboCop の主要ルール抜粋（CLAUDE.md へリンクするだけでも可）。
- Brakeman / bundler-audit を PR 時に確認。

### 12. デプロイ

- Kamal（Docker ベース）。設定は `config/deploy.yml` と `Dockerfile`。
- ブランチ戦略: `feat/xxx` → `develop`、`develop → main` のリリース PR は GitHub Actions
  で自動生成。

### 13. 開発フロー（Claude Code）

既存 README を踏襲（`/start-with-plan` → `/code-review` → `/pr-creation`）。
進行中の方針ドキュメントは `docs/tasks/21-` 〜 `25-` を参照、と一行添える。

### 14. 参照

- `CLAUDE.md`: プロジェクトルール、Docker / Makefile / RuboCop 規約
- NxTECH Workspace: 「プロダクト落とし所 v5: 3層アーキテクチャ」設計思想
- [Ridgepole](https://github.com/ridgepole/ridgepole)
- [Solid Queue / Solid Cache / Solid Cable](https://github.com/rails/solid_queue)

## 実装ステップ

1. `develop` から `feat/update-readme-with-domain-overview` ブランチを切る
   （メモリ `feedback_feature_branch_required.md` に従う）。
2. 削除対象ファイル（`docs/tasks/00-overview.md`, `01-` 〜 `20-`,
   `dedupe-test-ci-on-release-pr.md` の計 22 ファイル）を `git rm` で削除。
3. README.md を上記章立て案に沿って全面書き直し。
   - `00-overview.md` から「3 層アーキ表」「ドメイン解説」「仕訳パターン」「API 一覧」
     「エラーコード表」「UserChannel ペイロード」を README 用に圧縮して引用。
   - 既存 README の「セットアップ」「環境変数表」「開発コマンド」「Claude Code フロー」
     は構造を尊重しつつ、Makefile のフル一覧に置き換える。
   - AuthCore セクションは 21〜25 へのリンクのみ。
4. ローカルで README をプレビューし、リンク切れ（21〜25 のパス）と Markdown 表崩れが
   ないか確認。
5. コミット → push → `develop` ベースで PR 作成（`/pr-creation` を想定）。

## テスト要件

- **Markdown 構文**: 章番号・見出しレベル・リンクパスが正しく、Markdown プレビューで
  崩れないこと。
- **削除確認**: `ls docs/tasks/` の結果が `21-add-external-user-id.md` 〜
  `25-auth-policy-application.md` の 5 ファイルのみであること。
- **リンク到達性**: README の「認証」セクションから 21〜25 への相対リンクが
  GitHub 上で 200 で開けること（PR プレビューで目視確認）。
- **コード影響なし**: `make rspec` / `make rubocop` は実行不要（変更がドキュメントのみ）。
  ただし PR 上で CI が緑であることは確認する。

## 技術的な補足

- `docs/tasks/21-` 〜 `25-` は AuthCore の `client_id` / `client_secret` 受領待ちの
  項目（特に #24）も含むため、本タスクで「実装中」「未着手」と区別する必要はなく、
  README からは「AuthCore 連携の実装方針はここを参照」と一括で導く。
- `00-overview.md` の「8. 個別タスク一覧」「依存グラフ」は README に持ち込まない
  （消化済みタスクへの参照になり実態と乖離するため）。MVP 計画の歴史的記録が
  必要になれば、Git ログから掘れる前提。
- `00-overview.md` の「2.2 非責務」（手数料口座・SNS Webhook・日次突合ジョブ・CORS・
  alba シリアライザ等）は README には載せない。読者ハイブリッド向けには情報量過多のため、
  必要になった時点で別途 `docs/architecture/` 等に切り出す方が望ましい。
- 既存 README の「技術スタック表」「セットアップ手順」「環境変数表」は実用情報として
  優秀なので、書き直しでも構造を残し、内容を更新する形にする（破棄しない）。
