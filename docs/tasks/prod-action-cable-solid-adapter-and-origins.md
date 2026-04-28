# prod-action-cable-solid-adapter-and-origins: production の ActionCable を Solid Cable + 非ブラウザ許可に揃える

## 概要

現状、本番環境で ActionCable が以下 2 点の問題により、モバイルクライアント（KMP アプリ）からの WebSocket 接続が機能しない見込み：

1. **`config/cable.yml` の production が `adapter: redis` / `REDIS_URL` 前提**
   - `Gemfile` には `solid_cable` が入っており、プロジェクト方針も Solid Cable 利用
   - しかし `compose.prod.yml` に Redis サービスは存在しない → 起動時または接続時に失敗する
2. **`config.action_cable.allowed_request_origins` 未設定**
   - Rails 8 デフォルトでは production 環境下で同一ホストのみ許可
   - ネイティブアプリからの接続は `Origin` ヘッダが空 or 非 Web オリジンのため拒否される

本タスクで `cable.yml` を `solid_cable` に切り替え、ネイティブアプリからの接続を許可する設定を追加する。

## 背景・目的

- `CLAUDE.md` 記載の通り本プロジェクトは **Solid Cable / ActionCable** 構成。`rails new` scaffold の初期値（Redis）が残っているだけなので修正。
- モバイルクライアント側 (`UserChannelClient`) が本番 `wss://api.fujupay.app/cable` に接続するための前提条件。
- `force_ssl` は既に production で有効なので、`wss://` で接続できる。

## 影響範囲

- ファイル: `config/cable.yml`, `config/environments/production.rb`
- スキーマ: Solid Cable 用テーブル（`solid_cable_messages` 等）が primary DB に作成される
  - ridgepole 管理下の `db/Schemafile` には Solid Cable テーブルを書かない。Solid Cable は自前のマイグレーション (`bundle exec rails solid_cable:install:migrations` 相当) を持つため、**初回デプロイ後に手動で `rails db:migrate` が必要かを確認**（Solid Cable の gem バージョンにより挙動差あり）
- 破壊的変更: なし（現状の production で cable が動いていないので壊れる機能はない）
- デプロイ影響: CD の既存スクリプト（ridgepole 適用）に加え、Solid Cable テーブルの作成が必要になる可能性

## 実装ステップ

1. **`config/cable.yml` の production を Solid Cable に差し替え**
   ```yaml
   production:
     adapter: solid_cable
     connects_to:
       database:
         writing: cable
     polling_interval: 0.1.seconds
     message_retention: 1.day
   ```
   - `cable` という名前のDB定義を `config/database.yml` の production 配下に追加する必要あり
     ```yaml
     production:
       primary: &primary_production
         ...
       cache:
         ...
       queue:
         ...
       cable:
         <<: *primary_production
         database: fuju_bank_backend_production_cable
         migrations_paths: db/cable_migrate
     ```
   - もしくは **primary に相乗り**（`database: writing: primary`）にすれば追加DB不要。シンプルさ優先なら相乗り推奨。

2. **Solid Cable のスキーマを適用する経路を決める**
   - Solid Cable は自身のマイグレーションファイルを `db/cable_migrate/` に配置する前提
   - ridgepole 管理下にしないため、**デプロイスクリプトに `rails db:migrate:cable` を追加** するか、primary 相乗りなら不要（`solid_cable_messages` テーブルが primary にあれば動く）
   - 最もシンプル: primary 相乗り + Solid Cable の初期マイグレーションを `db/Schemafile` に手書きで追加（ridgepole 一元管理）

3. **`config/environments/production.rb` に ActionCable origin 許可を追加**
   ```ruby
   config.action_cable.allowed_request_origins = [
     %r{https?://api\.fujupay\.app}
   ]
   # ネイティブアプリからは Origin ヘッダが付かないため、Forgery Protection を無効化する
   config.action_cable.disable_request_forgery_protection = true
   ```
   - **セキュリティ注意**: `disable_request_forgery_protection = true` はクロスオリジンからの WebSocket 接続を一律許可する。認証は Connection#connect 内で JWT 等で行うこと前提。MVP で認証未実装なら一時的に開放するがコメントで明記。

4. **（オプション）`compose.prod.yml` から不要な Redis 参照を削除**
   - 現状 Redis サービスは無いので特に変更不要

5. **CD デプロイスクリプト更新**
   - primary 相乗り方針なら既存の `ridgepole --apply` 1 本で済む
   - 別DB分離方針なら `rails db:migrate:cable` を追加

## 検証チェックリスト

- [ ] ローカル（dev）で `config/cable.yml` の production を模した設定を読み込んでも Rails が起動する
- [ ] 本番デプロイ後、`curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" https://api.fujupay.app/cable` が 426/101 を返す（ハンドシェイク到達）
- [ ] クライアントから `wss://api.fujupay.app/cable` 接続が開ける（Step 3 スモークテストで検証）
- [ ] 本番ログに `Successfully upgraded to WebSocket` が出る

## 依存

- なし（本タスク単体で完結）

## 技術的な補足

- **primary 相乗り vs 分離の判断**
  - MVP: 相乗りで十分。運用負荷が低い
  - 将来 cable メッセージが膨らんで primary に負荷をかけ始めたら分離
- **Solid Cable のテーブル管理について**
  - gem 付属のマイグレーションを使うか、`db/Schemafile` に手書きで加えるか
  - 本プロジェクトは ridgepole 一元管理が方針なので、**`db/Schemafile` に手書き** が一貫性あり
  - 参考: `solid_cable_messages` テーブル1本だけ。下記で足りる想定（要バージョン確認）
    ```ruby
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false
      t.index [:channel], length: 40
      t.index [:channel_hash]
      t.index [:created_at]
    end
    ```
- **認証とフォージェリ保護**
  - 本番運用時は `ApplicationCable::Connection#connect` で JWT or トークン検証を実装し、`disable_request_forgery_protection = true` でも安全な状態にする
  - 本タスクのスコープ外。AuthCore 方針（`auth-strategy-decision.md`）が固まった後に追実装
