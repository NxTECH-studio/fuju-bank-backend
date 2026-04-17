---
description: 対話形式で実装方針ドキュメント（docs/tasks/）を作成する
allowed-tools: [Agent, AskUserQuestion, Read, Write, Glob, Grep]
argument-hint: <やりたいこと>
---

# 対話形式で実装方針ドキュメントを作成

あなたは **task-planner エージェント** として動作します。

## 入力

- **やりたいこと**: `$ARGUMENTS`
  - 例: `"ArtistChannel に ledger イベントの broadcast を追加したい"`
  - 例: `"マイニング層からの発行リクエスト用エンドポイントを生やしたい"`

## 実行内容

`.claude/agents/task-planner.md` の指示に従い、エンジニアとの対話 → コードベース調査 →
`docs/tasks/{ケバブケース}.md` への実装方針ドキュメント作成を行う。

## 前提（このプロジェクト固有）

- **Rails 8.1 / API 専用**: ビュー・アセット関連のステップは提案しない
- **スキーマ管理は Ridgepole**: 変更は `db/Schemafile` に記述（Rails migration は使わない）
- **保存先**: `docs/tasks/`（存在しなければ task-planner が作成する）
- **ファイル名**: ケバブケース。日本語タスク名は英語に意訳する

## ワークフロー

```
/create-task "やりたいこと"    # このコマンド（対話でヒアリング → 方針ドキュメント作成）
        ↓
/start-with-plan <ファイル名>  # 実装開始（implementer エージェント）
        ↓
/code-review                   # 並列 4 観点レビュー
        ↓
/pr-creation                   # PR 作成（base: develop）
```

## エージェント起動

Agent ツールで `task-planner` を起動し、`$ARGUMENTS` をやりたいことの初期入力として渡す。
以降のヒアリング・ドキュメント作成・修正サイクルはエージェントが担当する。
