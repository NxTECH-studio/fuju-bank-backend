# Fuju Bank Backend

Rails 8.1 API専用バックエンドアプリケーション。

## 技術スタック

| カテゴリ | 技術 |
|---|---|
| 言語 | Ruby 4.0.2 |
| フレームワーク | Rails 8.1 (API only) |
| DB | PostgreSQL |
| スキーマ管理 | Ridgepole |
| バックグラウンドジョブ | Solid Queue |
| キャッシュ | Solid Cache |
| デプロイ | Kamal (Docker) |
| テスト | RSpec, FactoryBot |
| Lint | RuboCop |

## セットアップ（Docker）

Docker を使って環境構築できます。PostgreSQL を含めたすべての依存をコンテナ内で完結させます。

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
make setup            # 初回セットアップ
make up / make down   # コンテナ起動 / 停止
make console          # Rails コンソール
make sh               # コンテナ内シェル
make rspec            # テスト実行（make rspec ARGS=spec/models/ で絞り込み可）
make rubocop          # RuboCop チェック
make rubocop/fix      # RuboCop 安全な自動修正
make rubocop/fix-all  # RuboCop 全自動修正（unsafe 含む）
make brakeman         # セキュリティ解析
make bundler-audit    # Gem 脆弱性スキャン
make db/schema/apply  # Ridgepole スキーマ適用
make db/reset         # DB再作成
make logs             # ログ表示
make clean            # コンテナ・ボリューム全削除
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

## 開発フロー（Claude Code）

このプロジェクトでは Claude Code のカスタムコマンドを活用した開発フローを採用しています。

```
1. /start-with-plan <方針ファイル>
   → 実装方針に沿ってコードを実装。

2. /code-review
   → 並列エージェントによるセルフレビュー（セキュリティ・設計・テスト・可読性・Lint）。

3. /pr-creation
   → PR 作成。

4. 人間がレビュー / マージ / QA / リリース
```

カスタムコマンドの定義は `.claude/commands/` を参照してください。
