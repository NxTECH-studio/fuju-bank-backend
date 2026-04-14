.DEFAULT_GOAL := help

# --------------------------------------------------
# Docker Compose
# --------------------------------------------------

.PHONY: build up down restart logs ps

build: ## コンテナをビルド
	docker compose build

up: ## コンテナをバックグラウンドで起動
	docker compose up -d

down: ## コンテナを停止・削除
	docker compose down

restart: ## コンテナを再起動
	docker compose restart

logs: ## ログをフォロー表示
	docker compose logs -f

ps: ## コンテナ状態を表示
	docker compose ps

# --------------------------------------------------
# Setup
# --------------------------------------------------

.PHONY: setup db/create db/schema/apply db/reset

setup: build ## 初回セットアップ（ビルド→起動→DB作成→スキーマ適用）
	docker compose up -d --wait
	docker compose exec web bundle install
	docker compose exec web bin/rails db:create || true  # DB既存の場合を許容
	docker compose exec web bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile
	docker compose exec web bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile

db/create: ## DB作成
	docker compose exec web bin/rails db:create

db/schema/apply: ## Ridgepoleでスキーマ適用（dev + test）
	docker compose exec web bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile
	docker compose exec web bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile

db/reset: ## DBをドロップして再作成
	docker compose exec web bin/rails db:drop db:create
	docker compose exec web bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile
	docker compose exec web bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile

# --------------------------------------------------
# Rails
# --------------------------------------------------

.PHONY: console bundle

console: ## Railsコンソール
	docker compose exec web bin/rails console

bundle: ## bundle install
	docker compose exec web bundle install

# --------------------------------------------------
# Test / Lint
# --------------------------------------------------

.PHONY: rspec rubocop rubocop/fix rubocop/fix-all brakeman bundler-audit

rspec: ## RSpecテスト実行
	docker compose exec web bundle exec rspec $(ARGS)

rubocop: ## RuboCopチェック
	docker compose exec web bundle exec rubocop

rubocop/fix: ## RuboCop安全な自動修正
	docker compose exec web bundle exec rubocop -a

rubocop/fix-all: ## RuboCop全自動修正（unsafe含む）
	docker compose exec web bundle exec rubocop -A

brakeman: ## Brakemanセキュリティ解析
	docker compose exec web bin/brakeman --no-pager

bundler-audit: ## Gem脆弱性スキャン
	docker compose exec web bin/bundler-audit

# --------------------------------------------------
# Shell
# --------------------------------------------------

.PHONY: sh

sh: ## webコンテナにシェルでアタッチ
	docker compose exec web bash

# --------------------------------------------------
# Cleanup
# --------------------------------------------------

.PHONY: clean

clean: ## コンテナ・ボリュームを全削除
	docker compose down -v

# --------------------------------------------------
# Help
# --------------------------------------------------

.PHONY: help

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_/\-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
