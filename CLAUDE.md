# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドです。

## プロジェクト概要

fuju-bank-backend — fuju-bank（感情を担保とする中央銀行）のバックエンド実装。Rails 8.1 API専用アプリケーション (Ruby 4.0.2, PostgreSQL)。

「ふじゅ〜」という仮想通貨の発行・記帳・決済・配信を司る。マイニングクライアント
（例: `glyca-mining`）や参照UI（例: `glyca-client-web`）から呼び出される、
3層アーキテクチャの **1層目（銀行層）**。

設計思想の系譜は NxTECH Workspace の「プロダクト落とし所 v5: 3層アーキテクチャ」を参照。

## よく使うコマンド

開発環境は Docker（`compose.yml`）で構築。Makefile 経由でコマンドを実行する。

```bash
# Docker操作
make setup                               # 初回セットアップ（ビルド→起動→DB作成→スキーマ適用）
make up                                  # コンテナ起動
make down                                # コンテナ停止

# テスト
make rspec                               # 全テスト実行
make rspec ARGS=spec/models/             # ディレクトリ単位で実行
make rspec ARGS=spec/models/user_spec.rb # ファイル単位で実行
make rspec ARGS=spec/models/user_spec.rb:42  # 行番号指定で実行

# Lint
make rubocop                             # 全チェック
make rubocop/fix                         # 安全な自動修正
make rubocop/fix-all                     # 全自動修正（unsafe含む）

# セキュリティ
make brakeman                            # 静的解析
make bundler-audit                       # Gem脆弱性スキャン

# データベース
make db/create                           # DB作成
make db/schema/apply                     # Ridgepoleスキーマ適用（dev + test）
make db/reset                            # DBドロップ→再作成→スキーマ適用

# その他
make console                             # Railsコンソール
make sh                                  # コンテナ内シェル
make logs                                # ログ表示
make help                                # コマンド一覧
```

### Docker を使わない場合（ローカル直接実行）

```bash
bin/rails server
bundle exec rspec
bundle exec rubocop
bundle exec rubocop -A
bin/brakeman --no-pager
bin/bundler-audit
bin/rails db:create
bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile
bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile
```

## ブランチ戦略

- **デフォルトブランチ**: `develop`（開発用）。PRのベースブランチは基本的に `develop` を指定する。
- **本番ブランチ**: `main`（ブランチ保護あり、直接push禁止）。リリース時に `develop → main` へのPRをマージする。
- **featureブランチ**: `feat/xxx` などのブランチを `develop` から切って作業し、`develop` へPRを出す。
- **リリースPR自動生成**: `develop` へのpush時に GitHub Actions で `develop → main` へのリリースPRが自動生成・更新される。

## アーキテクチャ

- **API専用**: ビュー/アセットなし。`config.api_only = true`。他の2層（マイニング、SNS）から呼び出される中央銀行。
- **スキーマ管理**: Railsマイグレーションではなく [Ridgepole](https://github.com/ridgepole/ridgepole) を使用。テーブル定義は `db/Schemafile` に記述（またはサブファイルをrequire）。
- **バックグラウンドジョブ**: Solid Queue（DBベースのActive Jobアダプタ）。
- **キャッシュ**: Solid Cache（DBベースのRails.cacheアダプタ）。
- **リアルタイム配信**: Solid Cable / ActionCable。`UserChannel` を通じてユーザー HUD へ ledger イベントを push。
- **開発環境**: Docker Compose（`compose.yml` + `Dockerfile.dev`）。Makefile でコマンドをラップ。
- **デプロイ**: Kamal（Dockerベース）。`config/deploy.yml` と `Dockerfile` を参照。
- **DB接続**: 環境変数 `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD` で設定。Docker環境では `compose.yml` で自動設定。

## コードスタイル (RuboCop)

デフォルトと異なる主要ルール:

- **文字列**: ダブルクォート（`"hello"`）。例外: Gemfile。
- **Hashショートハンド**: 禁止 — 常に `key: value` を使い、`key:` 省略記法は使わない（`Style/HashSyntax: never`）。
- **末尾カンマ**: 複数行の引数・配列・ハッシュでは必須。
- **モジュールスタイル**: コンパクト形式（`class Foo::Bar`、ネストしない）。
- **行の長さ**: 最大160文字（specファイルは制限なし）。
- **Lambda記法**: リテラル（`-> { }`、`lambda { }` は使わない）。
- **`let` vs `let!`（RSpec）**: カスタムcop `RSpec/PreferLetBang` が有効 — `let!` を優先。
- **ドキュメント**: モデル・ジョブ・サービスにはクラスコメント必須（基底クラスは除く）。
- **述語メソッドの接頭辞**: `is_` は禁止（`is_active?` ではなく `active?`）。

## テスト

- RSpec + FactoryBot（`create`, `build` 等はメソッドとして直接利用可能）。
- `database_rewinder` でDBクリーンアップ。
- `bullet` でN+1検出。
- `test-prof` でプロファイリング。
- SimpleCovはCIで有効（`CI=true` または `COVERAGE=true`）。
- `TimeHelpers` 組み込み済み — `travel_to`, `freeze_time` 等が使える。
