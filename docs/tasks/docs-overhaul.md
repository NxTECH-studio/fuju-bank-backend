# docs-overhaul: ドキュメント横断リファクタ（README / CLAUDE.md / docs/tasks 整理）

## 概要

ハッカソン文脈で公開も視野に入れつつ、Claude Code / 新規参画者の双方が「現状を正しく読める」
状態にするため、`README.md` / `CLAUDE.md` / `docs/tasks/` 配下のドキュメントを 1 PR でまとめて
整える。Ruby / Rails / Ridgepole / Solid Queue / Solid Cache / Solid Cable / 認証実装の
**現在の実態**に合わせ、古い記述（`.kamal/` / `gem "kamal"` / 重複記述 / 消化済み計画）を
取り除き、不足していた認証・記帳モデルの解説と `docs/tasks/` のインデックスを追加する。

## 背景・目的

- `.kamal/` ディレクトリと `Gemfile` の `gem "kamal"` が残ったまま運用は GitHub Actions +
  docker compose に移行している。`CLAUDE.md` には「旧スキームの残骸」と注記されているが、
  `Gemfile.lock` にも `kamal (2.11.0)` が常駐しており、`bundle install` のたびに不要 Gem を
  落としている。
- `README.md` と `CLAUDE.md` で「セットアップ」「Makefile コマンド一覧」「コードスタイル」
  「アーキテクチャ」が二重管理になっており、片方だけ更新されて drift する温床になっている。
- `docs/tasks/` 配下にはインデックスが無く、`b1-` 〜 `b6-` / `prod-action-cable-...` /
  `qr-payment-foundation-mpm/` / `update-readme-with-domain-overview.md` /
  `post-env-switch-roadmap.md` が並列に並んでいるだけで、どれが完了 / 進行中 / 計画中なのか
  ファイルを開かないと判別できない。
- `CLAUDE.md` のアーキテクチャ節は箇条書き 8 行で、認証 concerns / Service Object 配置 /
  記帳モデル / Channel 構成といった「実装時に必要な知識」が薄い。Claude Code が新規タスクで
  類似実装を探すたびに `app/` 配下を grep しないと文脈が組めない。
- ハッカソン文脈（本番品質より「動くこと優先」）を踏まえ、過剰なドキュメント体系の作り込み
  （`docs/architecture/` を新設して階層化する等）はしない。**README に集約 +
  `docs/tasks/INDEX.md` を 1 枚追加** するのが落とし所。

## 影響範囲

- **変更対象**:
  - `README.md`（公開用に整える、CLAUDE.md と重複していた箇所を README 主・CLAUDE 従に整理）
  - `CLAUDE.md`（README に書いてあることはリンクで参照、Claude が必要とする実装情報を拡充）
  - `Gemfile`（`gem "kamal"` を削除）
  - `Gemfile.lock`（`bundle install` で再生成）
  - `.kamal/`（ディレクトリごと削除）
  - `.dockerignore`（`/.kamal` の行を削除、`/config/deploy*.yml` も Kamal 残骸として削除）
  - `docs/tasks/INDEX.md`（新規、1 枚で全タスクのステータスを俯瞰）
  - `docs/tasks/qr-payment-foundation-mpm.md`（「移動済み」スタブ。本人が「削除して問題ない」と
    宣言しているので削除）
  - `docs/tasks/update-readme-with-domain-overview.md`（既に消化済みのリファクタ計画書、本タスクで
    後続として上書きされる位置づけのため削除）
- **破壊的変更**: なし（コード / API / スキーマは触らない）
- **外部層（マイニング / SNS）への影響**: なし
- **コード影響**: `Gemfile` 1 行のみ。`make rspec` / `make rubocop` には影響しない想定。

## スキーマ変更

なし。

## サブタスクと実装ステップ

サブタスクは A → B → C → D → E の順で実施する（A が最も独立、E が最も統合的なため、
進めるほど他サブタスクの結果を README に集約しやすい）。**1 PR で全部一気にまとめてよい**
（横断リファクタとして）。

---

### A. `.kamal/` 残骸の削除

**目的**: 物理的に残った Kamal 由来ファイルを除去し、`Gemfile` / `Gemfile.lock` から
`kamal` を落とす。`CLAUDE.md` の「旧スキームの残骸」注記が不要になる。

**対象ファイル**:
- `.kamal/`（ディレクトリ全削除：`.kamal/secrets`, `.kamal/hooks/*.sample` 全 8 個）
- `Gemfile`（`# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]`
  コメント行と `gem "kamal", require: false` 行を削除）
- `Gemfile.lock`（`bundle install` で再生成）
- `.dockerignore`（`# Ignore Kamal files.` ブロック全体 — 該当行は `28` 〜 `32` 周辺の
  `/.kamal` と `/config/deploy*.yml` を含む 3 行）

**手順**:
1. `git rm -r .kamal`
2. `Gemfile` から Kamal 行を削除（コメント行込みで 2 行）
3. `bundle install` を Docker 内で実行し `Gemfile.lock` を更新（`make sh` 経由 or `make bundle`）
4. `.dockerignore` の Kamal 関連行を削除
5. `make rspec` / `make rubocop` を実行して回帰がないことを確認

**受け入れ基準**:
- `rg -i kamal` がリポジトリ全体で 0 ヒット（CLAUDE.md / README.md / `docs/tasks/` の記述含めて）
- `bundle list | grep -i kamal` で何も出ない
- `make rspec` / `make rubocop` が緑

---

### B. README.md と CLAUDE.md の役割分離

**目的**: 現状の重複（セットアップ手順 / Makefile 一覧 / コードスタイル / アーキテクチャ概要）を
解消し、**README は「人間向け公開ドキュメント」**、**CLAUDE.md は「Claude Code 向け規約 + 実装の
ナビ」** という役割に明確化する。

**役割分担の原則**:

| 内容 | README.md | CLAUDE.md |
|---|---|---|
| プロジェクト概要 / 3 層アーキ / ドメイン / API / Cable / 認証 / 技術スタック | 主（詳細） | 従（README に誘導） |
| セットアップ / 環境変数 / Makefile 一覧 | 主（詳細） | 従（「README 参照」のみ） |
| ブランチ戦略 / デプロイ手順 | 主（詳細） | 従（README に誘導） |
| RuboCop ルール（プロジェクト固有の差分） | 簡潔（「CLAUDE.md 参照」） | **主（詳細）** |
| RSpec 規約（`let!` 強制 / FactoryBot / TimeHelpers 等） | 簡潔 | **主（詳細）** |
| 実装ナビ（Service / Job / Channel / Concern の配置と役割） | なし | **主（詳細、D で拡充）** |
| docs/tasks の使い方（`/start-with-plan`） | 簡潔リンク | 主（詳細） |

**具体的な編集**:

1. `CLAUDE.md` の「よく使うコマンド」「Docker を使わない場合」セクションを縮約し、
   「詳細は [README.md の Makefile 一覧](./README.md#開発コマンドmakefile) 参照」に置き換える。
   主要コマンド（`make rspec`, `make rubocop`, `make rspec ARGS=...`）は Claude が頻繁に使うため、
   1 ブロックだけ残す。
2. `CLAUDE.md` の「ブランチ戦略」を README に集約済みなので、CLAUDE.md 側は「詳細は README の
   ブランチ戦略 参照。Claude は `develop` から `feat/xxx` を切って PR を出す」の 1〜2 行に縮約。
3. `CLAUDE.md` の「アーキテクチャ」の `.kamal/` 注記を削除（A で物理削除されるため）。
4. `CLAUDE.md` の「アーキテクチャ」全体を D の拡充版で置き換える。

**受け入れ基準**:
- README と CLAUDE.md で同じ Makefile コマンド表が二度出てこない
- README と CLAUDE.md で同じセットアップ手順（`make setup` → `make up` → ...）が二度出てこない
- CLAUDE.md の冒頭で「README.md を先に読むこと」が明示されている

---

### C. `docs/tasks/INDEX.md` を新規作成

**目的**: タスクのステータスを 1 ファイルで俯瞰できるようにする。タスクファイル本体に
ステータスを書き込まないのは「横断確認のしやすさ」と「タスクファイル本体の改変を避ける」ため。

**作成内容**: `docs/tasks/INDEX.md` に以下の表を作る。

```markdown
# docs/tasks インデックス

`/start-with-plan {ファイル名}` で実装に取り掛かれる粒度の方針ドキュメント置き場。
ステータスは本ファイルで一元管理する（タスクファイル本体には書き込まない）。

## ロードマップ系

| ファイル | 概要 | ステータス |
|---|---|---|
| [post-env-switch-roadmap.md](./post-env-switch-roadmap.md) | env 切り替え後に本番稼働まで必要な実装計画（B1〜B6 のハブ） | 進行中 |

## B1〜B6（認証・本番化フェーズ）

| ファイル | 概要 | ステータス |
|---|---|---|
| [b1-cable-connection-jwt-auth.md](./b1-cable-connection-jwt-auth.md) | ActionCable Connection に JWT 認証を導入 | 完了 / 進行中 / 未着手（要確認） |
| [b2-users-lazy-provisioning.md](./b2-users-lazy-provisioning.md) | Users#create を lazy provisioning に置き換え | 完了（実装済み） |
| [b3-cors-policy.md](./b3-cors-policy.md) | CORS 方針決定と適用 | 完了（CLAUDE.md / README に方針反映済み） |
| [b4-authcore-deploy-and-client-registration.md](./b4-authcore-deploy-and-client-registration.md) | AuthCore のデプロイと bank client 登録 | （要確認） |
| [b5-cd-env-injection-and-worker.md](./b5-cd-env-injection-and-worker.md) | CD への AUTHCORE_* 注入 / Solid Queue worker / ドキュメント更新 | （要確認） |
| [b6-auth-e2e-smoke.md](./b6-auth-e2e-smoke.md) | 認証 E2E 疎通テスト | 未着手 |

## 個別タスク

| ファイル | 概要 | ステータス |
|---|---|---|
| [prod-action-cable-solid-adapter-and-origins.md](./prod-action-cable-solid-adapter-and-origins.md) | production の ActionCable を Solid Cable + 非ブラウザ許可に揃える | 完了 |
| [qr-payment-foundation-mpm/](./qr-payment-foundation-mpm/) | QR 決済基盤 (MPM) MVP（STEP 01〜07） | 進行中 / 未着手（要確認） |

## 削除済み（履歴のみ Git ログから復元可能）

- `00-overview.md` 〜 `25-auth-policy-application.md`（MVP 計画 + AuthCore 連携、消化済み）
- `dedupe-test-ci-on-release-pr.md`
- `qr-payment-foundation-mpm.md`（スタブ。中身は `qr-payment-foundation-mpm/` ディレクトリへ移動済み）
- `update-readme-with-domain-overview.md`（消化済み、本タスク docs-overhaul で後続）
```

**ステータス記入の決め方**:
- 「完了」「進行中」「未着手」「要確認」の 4 値で十分。
- 各タスクのステータスはエンジニア（user）に確認しながら埋める。INDEX 草案では
  「（要確認）」と書いておき、PR 内で対話的に確定させる。

**受け入れ基準**:
- `docs/tasks/INDEX.md` 単体を見れば、どのタスクが進行中で、何が消化済みで、何が未着手か分かる
- README から `docs/tasks/INDEX.md` への 1 リンクのみ貼る（個別タスクへのリンクは
  README に貼らない、INDEX に集約する）

---

### D. CLAUDE.md に認証・記帳モデル・Service / Job / Channel の実装ナビを拡充

**目的**: Claude Code が新規タスクで類似実装を探すときに、`app/` を grep する前に
`CLAUDE.md` だけで当たりがつけられる状態にする。各論は `app/` のファイルパスで参照させる。

**追記する節（CLAUDE.md の「アーキテクチャ」を以下の構成に置き換える）**:

```markdown
## アーキテクチャ

### 全体像
（README の「3 層アーキテクチャでの位置づけ」「主要ドメイン」「記帳モデル」を参照）

### ディレクトリ構成（実装時のナビ）

#### app/controllers/
- `application_controller.rb` — ベース。`JwtAuthenticatable` を全 action に適用。
  `current_external_user_id` / `current_user` ヘルパを供給。
- `concerns/jwt_authenticatable.rb` — Authorization: Bearer の RS256 ローカル検証。
  `service_actor_allowed!` を宣言したコントローラは type=service も受理。
- `concerns/introspection_required.rb` — AuthCore /v1/auth/introspect を毎回叩く。
  金銭移動系（LedgerController）のみ include。
- `concerns/mfa_required.rb` — `introspection_result.mfa_verified?` を要求。未適用箇所あり。
- `concerns/idempotent.rb` — Idempotency-Key ヘッダの取り回し。
- `concerns/error_responder.rb` — 統一エラーレスポンス（`error.code` / `error.message`）。
- `users_controller.rb` / `user_transactions_controller.rb` / `artifacts_controller.rb` /
  `ledger_controller.rb` — リソース別エンドポイント。

#### app/models/
- `user.rb` — `external_user_id`（AuthCore の sub, ULID 26 文字）で同定。
  `after_create` で `Account(kind: "user")` を 1:1 で生成。
- `artifact.rb` — `location_kind` enum (`physical` / `url`)。
- `account.rb` — `kind` enum で `system_issuance` / `user` / `store` を区別。
  `balance_fuju` は `ledger_entries.amount` の SUM キャッシュ。
- `ledger_transaction.rb` — `kind` (`mint` / `transfer`) / `idempotency_key` (unique) /
  `metadata` JSONB。`SUM(entries.amount) = 0` を validation で保証。
- `ledger_entry.rb` — 複式簿記の片側。1 トランザクションに必ず 2 行以上。
- `store.rb` — QR 決済基盤（MPM）用の店舗エンティティ（`docs/tasks/qr-payment-foundation-mpm/` 参照）。

#### app/services/
- `ledger/mint.rb` — Artifact → User の発行サービス。
  `ActiveRecord::Base.transaction` で原子性を担保し、成功時に `Ledger::Notifier` を呼ぶ。
- `ledger/transfer.rb` — User → User の送金サービス。残高不足は `INSUFFICIENT_BALANCE`。
- `ledger/notifier.rb` — `UserChannel` への broadcast を担当。
- `user_provisioner.rb` — JWT 検証成功時に sub から User + Account を lazy 作成。
  `ActiveRecord::RecordNotUnique` を rescue して並行リクエストを吸収。
- `authcore/jwt_verifier.rb` — RS256 / aud / iss / exp / type を検証する責務。
  Connection / Controller 双方から使う。
- `authcore/introspection_client.rb` — AuthCore /v1/auth/introspect のクライアント。
  RFC 7662 準拠。Basic Auth + form。
- `authcore/introspection_result.rb` — introspection レスポンスの値オブジェクト
  (`active?` / `mfa_verified?` / `scope` 等)。

#### app/channels/
- `application_cable/connection.rb` — JWT 認証を Connection レイヤで実施
  （subprotocol `Sec-WebSocket-Protocol: bearer, <jwt>`）。
- `application_cable/channel.rb` — ベース。
- `user_channel.rb` — 受け手 User へ `credit` イベントを broadcast。
  `current_user` に対して `stream_for` する形が安全。

#### app/jobs/
（必要に応じて追加。Solid Queue で `bin/jobs` または compose の `worker` が消化）

### 主要な不変条件（実装時に壊さない）

| 制約 | 実装場所 |
|---|---|
| `SUM(ledger_entries.amount) = 0` per transaction | `LedgerTransaction` の validation |
| `accounts.balance_fuju >= 0 WHERE kind = 'user'` | DB の CHECK 制約（部分制約） |
| `ledger_transactions.idempotency_key` unique | DB のユニーク制約 |
| mint / transfer 処理の原子性 | `ActiveRecord::Base.transaction` で囲む |
| 受取人の cross-service 同定 | `users.external_user_id` (= AuthCore の sub) で行う |

### スキーマ管理

Rails マイグレーションではなく [Ridgepole](https://github.com/ridgepole/ridgepole) を使用。
テーブル定義は `db/Schemafile` に直書き or サブファイル require。
**Claude が新規タスクで「migration を作る」ことを提案してはいけない**。`db/Schemafile` を編集し、
`make db/schema/apply` で dev / test に適用する。

### バックグラウンド / Cache / Cable

- Solid Queue（Active Job アダプタ）/ Solid Cache（Rails.cache アダプタ）/ Solid Cable
  （ActionCable アダプタ）。すべて DB ベースで Redis 不要。
- production の Cable adapter / allowed_request_origins / hosts は
  `docs/tasks/prod-action-cable-solid-adapter-and-origins.md` に経緯あり。

### CORS

ネイティブクライアントのみ運用のため CORS 設定不要。`config/initializers/cors.rb` は
無効化済みで、`rack-cors` Gem も導入していない。ブラウザクライアントから叩く要件が出たら
`docs/tasks/b3-cors-policy.md` の選択肢 (b) に従って `rack-cors` を再導入する。

### デプロイ

GitHub Actions (`.github/workflows/cd.yml`) が `main` push 時に Tailscale + SSH で
Proxmox CT に入り、`docker compose -p fuju-bank-prod -f compose.prod.yml up -d --build` を実行。
本番イメージは `Dockerfile.prod`。
（旧 Kamal 由来のファイルは削除済み — 詳細は `docs/tasks/docs-overhaul.md`）
```

**受け入れ基準**:
- Claude が「ledger 系のサービスはどこ？」「authcore 連携の検証はどこ？」と聞かれたとき、
  `CLAUDE.md` だけ読めばファイルパスに辿り着ける
- 不変条件 5 行が表形式で参照しやすく載っている
- 「Ridgepole 前提、migration 提案禁止」が明記されている

---

### E. README.md をハッカソン公開向けに整える

**目的**: README は既に十分な内容（310 行、概要 / ドメイン / 記帳モデル / API / Cable / 認証 /
セットアップ / 環境変数 / Makefile / デプロイ）を持っているので、**大改修はしない**。
ハッカソン公開時に「読み手が最初に詰まりがちな箇所」だけピンポイントで補強する。

**最小限の編集**:

1. **冒頭にバッジ / 一行要約を整える**（オプション）
   - 「Rails 8.1 / Ruby 4.0.2 / PostgreSQL / Ridgepole / Solid Queue・Cache・Cable」を
     3 層アーキ表のすぐ下に 1 行で書く（既に「技術スタック」表があるので重複ならスキップ）。

2. **「3 層アーキテクチャでの位置づけ」表に相互リポジトリのリンクを追加（あれば）**
   - 2 層目（マイニング）/ 3 層目（SNS）の GitHub URL が公開なら表の脚注に書く。
     非公開なら「公開時に追記」とだけ書いて TBD にしておく（深追いしない）。

3. **「参照」セクションに `docs/tasks/INDEX.md` を追加**
   - C で作る INDEX へのリンクを 1 行追加。

4. **CLAUDE.md と重複していた節を縮約**
   - B の役割分担に従い、README は「主」のままにする（README は読まれる方なので削らない）。

5. **公開時に伏せたいシークレット類が文書中にないか確認**
   - `AUTHCORE_CLIENT_SECRET` 等は「（secret 経由で注入）」のままで OK（既にその表記）。
   - `https://api.fujupay.app` / `https://auth.fujupay.app` のドメイン名は本番ドメインだが、
     既に `docs/tasks/post-env-switch-roadmap.md` 等で公開済みなので問題なし。

**しないこと（過剰作り込み回避）**:
- スクリーンショット / GIF の追加
- `docs/architecture/` 等の階層化
- 英語版 README 作成
- CONTRIBUTING.md の新規作成

**受け入れ基準**:
- README が「公開リポジトリで初見の人が `make setup` まで詰まらず辿り着ける」
- 機密値（client_secret 等）が直書きされていない
- `docs/tasks/INDEX.md` への参照リンクが追加されている

---

## 実施順序（推奨）

```
A (.kamal 削除) ─┐
                  ├─→ B (README/CLAUDE 役割分離) ─→ D (CLAUDE.md 拡充) ─→ E (README 微修正)
                  └─→ C (docs/tasks/INDEX.md 作成) ──────────────────────┘
```

A は他から独立。B は CLAUDE.md / README.md の両方を編集する起点。C は B と並行可能。
D は B の上で CLAUDE.md を肉付け。E は最後に全体を見ながら微調整。

**1 PR にまとめて出す前提**（横断リファクタなので分割しない）。

## テスト要件

- **コード非影響**:
  - `make rspec` が緑（A の `bundle install` で副作用が出ないこと）
  - `make rubocop` が緑
  - `make brakeman` が緑（既存の状態を維持）
- **kamal 残骸ゼロ**: `rg -i kamal` がリポジトリ全体で 0 ヒット
- **重複ゼロ**:
  - `Makefile コマンド表` が README / CLAUDE.md の両方に存在しないこと（grep `make rspec` が
    README に固まっていること）
  - セットアップ手順（`make setup`）が CLAUDE.md にフルで重複していないこと
- **INDEX 整合性**: `docs/tasks/INDEX.md` に列挙したファイルが実在し、列挙されていない
  ファイルが `docs/tasks/` 直下に無いこと（`qr-payment-foundation-mpm/` 配下のサブファイルは
  ディレクトリ単位で 1 行扱い）
- **公開準備**: README の `AUTHCORE_*` 系の機密値が「（secret 経由で注入）」表記のままで、
  実値が漏れていないこと

## 技術的な補足

- **ハッカソン文脈**: 本タスクはドキュメントのみ。コード変更は `Gemfile` の 1 行
  （`gem "kamal"` 削除）と `Gemfile.lock` の再生成のみ。`make rspec` への影響はゼロ前提。
- **`docs/tasks/INDEX.md` のステータス確定**: 各タスクの完了 / 未完了は本タスク作成者が
  すべて把握しているわけではないので、PR 内でエンジニアと対話しながら埋める。
  草案では「（要確認）」と置く。
- **`docs/tasks/update-readme-with-domain-overview.md` の扱い**: 内容は既に消化済み（README が
  ドメイン概要中心に刷新済み）。本タスク `docs-overhaul.md` がその後継位置づけになるので、
  削除してよい。
- **`docs/tasks/qr-payment-foundation-mpm.md` のスタブ**: 本人が「削除して問題ありません」と
  ファイル末尾に明記しているので、削除する。
- **CLAUDE.md の Ruby バージョン記述**: 「Ruby 4.0.2」は実態通りで正しい（前回の指摘は誤り）。
  本タスクでは触らない。
- **将来の拡張**: `docs/architecture/` を新設してドメイン図を切り出す等は本タスクの責務外。
  必要が出たときに別タスクで切る。
