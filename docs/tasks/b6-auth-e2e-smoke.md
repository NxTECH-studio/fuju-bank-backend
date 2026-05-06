# B6: 認証 E2E 疎通テスト

## メタ情報

- **Phase**: 2（B1〜B5 完了後）
- **並行起動**: ❌ B1 / B2 / B4 / B5 が本番に乗っていることが前提
- **依存**: B1 / B2 / B4 / B5
- **同期点**: app セッションでも E2E が緑になっていることを確認

## 概要

AuthCore → bank → UserChannel まで本番ドメインで一度通したことがない状態を解消する。1 コマンドで E2E が回る script を作り、CI で nightly に走らせる。

## 背景・目的

- 個別タスクの spec が緑でも、本番 ENV / TLS / reverse proxy / cookie / ActionCable subprotocol までを通した E2E は別物。
- 認証経路は変更頻度が高い + 壊れた時の影響がデカいので CI で常時監視したい。

## 影響範囲

- 新規 `script/e2e_smoke.rb`（or shell）
- `.github/workflows/e2e-nightly.yml`（新規）
- staging / production どちらで回すかは判断（最初は staging or 専用テストユーザーで production）

## 実装ステップ

1. **E2E script** (`script/e2e_smoke.rb`):
   1. AuthCore に test user を register（既存ならスキップ）
   2. `POST /v1/auth/login` で access_token + refresh cookie 取得
   3. bank `POST /users/me` を access_token で叩く → 201 / 200
   4. bank `GET /users/me` で残高 / プロフィール
   5. bank `POST /ledger/transfer`（or `/ledger/mint`）で別ユーザに送金
   6. bank `wss://api.fujupay.app/cable` に subprotocol JWT で接続 → broadcast を 5 秒以内に受信
   7. AuthCore `POST /v1/auth/logout`
   - 各ステップで失敗したら exit 1 + 失敗箇所を出力
   - 環境変数で AUTHCORE_BASE_URL / BANK_BASE_URL を切替可能

2. **GitHub Actions workflow** (`.github/workflows/e2e-nightly.yml`):
   - schedule: cron 毎日朝
   - secrets: テストユーザー credentials, AUTHCORE_* (introspection 用)
   - 失敗時 Slack 通知（既存 webhook あれば）

3. **テストデータ管理**:
   - 専用 test user を AuthCore に予め作っておく（毎回 register せず idempotent に動かすため）
   - 残高は test user 同士で循環させる（増減せず）

## 検証チェックリスト

- [ ] `bundle exec ruby script/e2e_smoke.rb` がローカル（docker compose 起動済）で緑
- [ ] GH Actions で 1 回手動実行して緑
- [ ] WebSocket broadcast が 5 秒以内に受信できる
- [ ] 失敗時に Slack 通知 or GH issue 自動作成
- [ ] nightly schedule が cron で走り始める
