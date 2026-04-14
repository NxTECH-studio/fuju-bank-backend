---
name: project-troubleshooting
description: プロジェクトのトラブルシューティング
---

## Pull Request

### `gh pr edit` で PR 概要欄を更新できない

**エラー**: `GraphQL: Projects (classic) is being deprecated...`

**原因**: このリポジトリに Projects (classic) が関連付けられているため、`gh pr edit` コマンドが GraphQL API でエラーを起こします。

**解決方法**: REST API を直接使用して更新します。

```bash
# 1. 更新内容をファイルに保存
cat > /tmp/pr_body.md <<'EOF'
## 概要
...（PR説明文）...
EOF

# 2. REST API で更新（-F オプションを使う）
gh api repos/NxTECH-studio/glyca-backend/pulls/{PR番号} -X PATCH -F body=@/tmp/pr_body.md
```

**ポイント**:
- `-f` ではなく **`-F`** を使う（`-F` はファイルの内容を送信）
- `gh pr edit` の代わりに `gh api` で REST API を直接呼び出す

---

## データベース

### スキーマ変更が反映されない

**原因**: このプロジェクトは Rails マイグレーションではなく Ridgepole を使用しています。

**解決方法**:
```bash
# development
bundle exec ridgepole -c config/database.yml -E development --apply -f db/Schemafile

# test
bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile
```

**ポイント**:
- `bin/rails db:migrate` は使わない
- テーブル定義は `db/Schemafile` に記述する
- development と test の両方に適用すること

---

## テスト

### RSpec 実行時に DB スキーマエラーが出る

**原因**: test 環境にスキーマが適用されていない可能性があります。

**解決方法**:
```bash
bundle exec ridgepole -c config/database.yml -E test --apply -f db/Schemafile
```

### Bullet が N+1 を検出した

**解決方法**: `includes` ではなく `preload` または `eager_load` を使用する。
```ruby
# 別クエリで読み込む場合
Model.preload(:association)

# JOIN が必要な場合
Model.eager_load(:association)
```
