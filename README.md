# fuju-bank-backend

fuju-bank（感情を担保とする中央銀行）の **バックエンド実装**。
「ふじゅ〜」という仮想通貨の発行・記帳・決済・配信を司る
Rails 8.1 API専用アプリケーション (Ruby 4.0.2, PostgreSQL)。

本リポジトリは **proof-of-feeling 型の中央銀行** の API 実装であり、マイニングクライアント
（例: `glyca-mining`）や参照UI（例: `glyca-client-web`）から呼び出される。

## 位置づけ

3層アーキテクチャの **1層目（銀行層）** に相当する。

```
┌─────────────────────────────────────┐
│ 3. デモ用SNS (別リポジトリ)          │
└─────────────────────────────────────┘
              ↕
┌─────────────────────────────────────┐
│ 2. マイニングシステム (別リポジトリ) │
└─────────────────────────────────────┘
              ↕ POST /api/encounters
┌─────────────────────────────────────┐
│ 1. 銀行システム (このリポジトリ)     │  ← ここ
└─────────────────────────────────────┘
```

## 基本要件

- **非可逆的発行**: 鑑賞者の「滞留時間」や「視線強度」という物理的コストのみを原資として新規発行される
- **不自由の記録（トランザクション）**: 単なる数値の移動ではなく、「誰が、どの作品に、何秒魂を削られたか」をメタデータとして保持
- **通貨の特性**: 基本的に「作家への感謝（負債）」であるため、作家が受け取った瞬間に価値が確定する

## 主要エンティティ

- **Artist (作家)**: ふじゅ〜の受け取り手。独自IDとHUD接続用の公開鍵を持つ
- **Artifact (作品)**: ふじゅ〜を生成する起点。物理場所またはURLと紐付く
- **GazeEvent (視線イベント)**: マイニングシステムから提出される proof-of-feeling
- **LedgerEntry (台帳エントリ)**: `artifact_id` から `artist_id` への「感情の譲渡」の不可逆な記録

## 技術スタック

glyca-backend と同じ構成を踏襲する。

- Ruby on Rails 8.1 (API only)
- Ruby 4.0.2
- PostgreSQL 17
- [Ridgepole](https://github.com/ridgepole/ridgepole) によるスキーマ管理
- Solid Queue（バックグラウンドジョブ）
- Solid Cache（キャッシュ）
- Solid Cable / ActionCable（リアルタイム配信）
- RSpec + FactoryBot（テスト）
- RuboCop（Lint）
- Brakeman / bundler-audit（セキュリティ）
- Docker Compose（開発環境）
- Kamal（デプロイ）

## セットアップ

> **注**: 本リポジトリは現状「設計書 + インフラのみ」の段階。Rails 本体（`app/`, `config/`, `Gemfile` 等）はまだ生成されていない。
> `rails new . --api --database=postgresql --skip-bundle` を実行して初期化する想定。

Rails 本体の生成後に以下が使える:

```bash
make setup   # 初回セットアップ（ビルド→起動→DB作成→スキーマ適用）
make up      # コンテナ起動
make rspec   # テスト実行
make help    # コマンド一覧
```

## ドキュメント

- [docs/api-contract.md](docs/api-contract.md) — 公開API契約（他2層との境界面）
- [CLAUDE.md](CLAUDE.md) — Claude Code 用の作業ガイド

## ブランチ戦略

- **デフォルト**: `develop`
- **本番**: `main`
- **feature**: `feat/xxx` を `develop` から切る

## プロジェクトの系譜

本プロジェクトは NxTECH Workspace における「ツクヨミ」プロジェクトの議論から派生した、
感情経済の中央銀行コンポーネントの独立実装である。設計経緯は Notion の
「プロダクト落とし所 v1〜v5」ページを参照。
