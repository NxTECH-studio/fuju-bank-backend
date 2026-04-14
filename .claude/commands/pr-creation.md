---
description: PR作成
---

# PR作成

## 現在の状況
- **現在のブランチ**: `{{bash: git rev-parse --abbrev-ref HEAD}}`
- **Base ブランチ**: `develop`

## 実行手順

### 1. コミット状態の確認
`git status` で確認:
- **未コミットあり**: 変更内容を分析して適切な粒度でコミット作成 → `git push -u origin ブランチ名`
- **コミット済み**: 次へ

### 2. 変更内容の分析
- `git diff develop...HEAD` 確認
- コミット履歴確認（`git log develop..HEAD`）

### 3. Linter最終確認（厳格）
**変更したファイルのみ**に対してRuboCopを実行:

```bash
git diff develop --name-only --diff-filter=AM | grep '\.rb$' | xargs -r bundle exec rubocop
```

**🚨 Linter警告・エラーへの対応（例外なし）🚨**

**重要: 変更したファイルの警告のみ対象**
- 上記コマンドは `git diff develop --name-only --diff-filter=AM` で**このブランチで変更したファイルのみ**を対象
- 変更していないファイルの警告は無視してOK
- **変更したファイルに出る警告・エラーはすべて修正必須**

**警告・エラーが1つでもある場合:**
- ❌ PR作成を中止
- ❌ 「機能には影響しない」「既存コードでも使用されている」などの言い訳は禁止
- ✅ すべての警告・エラーを修正してから再実行

**よくあるRuboCop警告の修正方法:**
- `RSpec/AnyInstance`: `allow_any_instance_of` を依存注入やモックオブジェクトに書き換え
- `Layout/LineLength`: 行を分割（160文字以内）
- `Style/HashSyntax`: ショートハンド禁止 — `key:` ではなく `key: value` を使う
- `RSpec/PreferLetBang`: `let` ではなく `let!` を使う

**変更したファイルの警告がすべて解消された場合のみ**: 次のステップへ進む

### 4. スキーマ変更の検出

`git diff develop -- db/Schemafile` で差分がある場合、次のステップのPR説明文「影響範囲・懸念点」にスキーマ変更の詳細を含める:
- 追加・変更・削除されたテーブル/カラム
- `bundle exec ridgepole --apply` の実行が必要な旨を記載

### 5. PR説明文の生成
`.github/pull_request_template.md` に従って作成:

**必須項目**:
- **概要**: 背景、目的、何をしたか
- **細かい変更点**: 主要な変更をリストで記述
- **影響範囲・懸念点**: 既存機能への影響、パフォーマンス懸念、Ridgepoleスキーマ変更の有無（Step 4の結果を反映）

**任意項目**:
- **その他**: 関連Issue・PR、参考リンク、レビュー時に見てほしいポイント

### 6. PR作成

```bash
gh pr create --base develop --title "タイトル（日本語）" --body "説明文" --assignee "@me"
```

作成されたPR URLを表示

## 注意事項
- タイトル・本文は**日本語**
- 影響範囲は過不足なく
- このプロジェクトのCIは **GitHub Actions** を使用（`.github/workflows/` 配下）
