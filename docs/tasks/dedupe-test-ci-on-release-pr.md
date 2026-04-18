# リリースPRで Test CI が二重実行される問題の解消

## 概要

`.github/workflows/test.yml` のトリガーから `push: branches: [develop]` を削除して
`pull_request` のみに寄せ、さらに `concurrency` 設定と `pull_request` の `branches`
絞り込みを追加する。これにより、リリースPR（develop → main）更新時などに Test CI
が二重実行される問題を解消する。

## 背景・目的

### 現状の症状

- `develop` ブランチへ push すると、以下が同時に走る:
  1. `push: branches: [develop]` トリガーによる Test 実行
  2. GitHub Actions によって自動生成・更新されるリリースPR（develop → main）の
     `pull_request` トリガーによる Test 実行
- 結果、同じコミット・同じ内容に対して Test が 2 回走り、CI 時間と Actions の
  使用枠を無駄に消費している。

### 原因

`.github/workflows/test.yml` のトリガー定義が `pull_request` と
`push: branches: [develop]` の両方を持っているため、develop への push が発生する
たびに両方のトリガーが発火する。

```yaml
on:
  pull_request:
  push:
    branches: [develop]
```

`develop → main` のリリースPRは develop へ push されるたびに自動更新される運用に
なっているため、push トリガーと pull_request (synchronize) トリガーが同時に走る
構造になっている。

### 目的

- 同一コミットに対する Test の重複実行を排除する。
- 連続 push 時には古いジョブを自動キャンセルして、常に最新コミットだけをテスト
  する。
- `pull_request` で反応するベースブランチを明示し、意図しない branch への PR
  での発火を防ぐ。

## 影響範囲

- **変更対象**: `.github/workflows/test.yml`（トリガー部分のみ）
- **破壊的変更**: なし（CI の検証対象は変わらず、発火経路の整理のみ）
- **外部層（マイニング / SNS）への影響**: なし
- **アプリケーションコード / DB / Ridgepole スキーマへの影響**: なし

## スキーマ変更

なし。

## 方針

### A 案（push を削除し pull_request に寄せる）を採用

選択肢として以下を検討した:

- **A: `push: branches: [develop]` を削除して `pull_request` のみに寄せる**
- B: `pull_request` を develop 宛てのみに絞って main 宛て PR は push でカバー
- C: workflow 側で `github.event_name` による分岐を入れる

A を採用する理由:

- feature → develop の PR、および develop → main のリリースPR の両方が
  `pull_request` トリガーに一本化できる。
- develop への直接 push は運用上行わない（PR 経由のマージのみ）ため、
  `push: branches: [develop]` は実質的にリリースPR 更新時の重複発火源にしか
  なっていない。
- `pull_request` トリガーだけにすれば、PR 単位で concurrency を効かせられる。

### concurrency 併用

同一 PR への連続 push 時に古いジョブを自動キャンセルする。`github.workflow` +
`github.ref` をキーにし、`cancel-in-progress: true` を付ける。

### `pull_request` の branches 絞り込み

`branches: [develop, main]` を明示し、develop / main 以外をベースにした PR では
Test が発火しないようにする（将来の作業ブランチ乱立への予防線）。

## 変更内容

### Before（現状）

`.github/workflows/test.yml` の冒頭:

```yaml
name: Test

on:
  pull_request:
  push:
    branches: [develop]

jobs:
  test:
    runs-on: ubuntu-latest
    ...
```

### After

```yaml
name: Test

on:
  pull_request:
    branches: [develop, main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    ...
```

変更ポイント:

1. `push: branches: [develop]` ブロックを削除。
2. `pull_request` に `branches: [develop, main]` を追加（develop / main を
   ベースブランチにする PR のみで発火）。
3. トップレベルに `concurrency` を追加し、同一 PR の連続 push で古いジョブを
   キャンセル。

`jobs:` 以降は変更なし。

## 実装ステップ

1. feature ブランチ（例: `feat/dedupe-test-ci`）を develop から切る。
2. `.github/workflows/test.yml` を上記 After の内容に編集する。
   - `push:` ブロックを削除
   - `pull_request:` に `branches: [develop, main]` を追加
   - トップレベルに `concurrency` ブロックを追加
3. PR を develop 宛てで作成する。この PR 自体で以下を確認:
   - Test が 1 回だけ走る（push + pull_request の二重発火が起きない）
   - Actions の一覧でワークフローが `pull_request` トリガーのみで動いている
4. マージ後、develop への反映タイミングでリリースPR（develop → main）が自動更新
   されるはずなので、そこで Test が 1 回だけ走ることを確認する。

## テスト要件 / 確認方法

- feature → develop の PR を push / 更新したとき、Test が **1 回だけ** 走る。
- 同一 PR に連続 push したとき、前のジョブが **キャンセル** されて最新コミット
  のジョブだけが走る（concurrency の効果）。
- 自動生成されるリリースPR（develop → main）が更新されたとき、Test が
  **1 回だけ** 走る（push トリガーと pull_request トリガーの二重発火が解消
  されている）。
- develop / main 以外をベースにする PR では Test が発火しないこと（必要に応じて
  別 branch をベースにしたダミー PR で確認、普段の運用上は発生しないので省略可）。

RSpec など Ruby 側の自動テストは追加不要（CI 設定変更のため）。

## ロールバック方法

- 変更をリバートする単独 PR を develop 宛てに出す。`git revert <commit>` で
  `.github/workflows/test.yml` を変更前の状態に戻すだけでよい。
- ロールバック後は再び push / pull_request の両トリガーで Test が走る構成に
  戻るため、CI 自体が壊れる心配はない。

## 技術的な補足

- `concurrency.group` に `github.ref` を使うことで、PR ごと（`refs/pull/<n>/merge`）
  に独立してキャンセル制御される。別 PR のジョブは影響を受けない。
- `pull_request` は既定で `opened`, `synchronize`, `reopened` に反応する。今回の
  目的（PR 更新時に 1 回走らせる）にはこれで十分なので `types:` は指定しない。
- 将来 main への hotfix 運用などで別フローを足す場合は、専用の workflow を
  別ファイルで追加する方針とし、本 workflow の責務は「PR 検証」に限定する。
