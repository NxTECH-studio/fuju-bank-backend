# docs/tasks インデックス

`/start-with-plan {ファイル名}` で実装に取り掛かれる粒度の方針ドキュメント置き場。
ステータスは本ファイルで一元管理する（タスクファイル本体には書き込まない）。

## ロードマップ系

| ファイル | 概要 | ステータス |
|---|---|---|
| [post-env-switch-roadmap.md](./post-env-switch-roadmap.md) | env 切り替え後に本番稼働まで必要な実装計画（B1〜B6 のハブ） | 進行中 |

## B1〜B6（認証・本番化フェーズ）

| ファイル | 概要 | ステータス |
|---|---|---|
| [b1-cable-connection-jwt-auth.md](./b1-cable-connection-jwt-auth.md) | ActionCable Connection に JWT 認証を導入 | 完了 |
| [b2-users-lazy-provisioning.md](./b2-users-lazy-provisioning.md) | Users#create を lazy provisioning に置き換え | 完了 |
| [b3-cors-policy.md](./b3-cors-policy.md) | CORS 方針決定と適用（ネイティブのみ運用に確定） | 完了 |
| [b4-authcore-deploy-and-client-registration.md](./b4-authcore-deploy-and-client-registration.md) | AuthCore のデプロイと bank client 登録 | 完了 |
| [b5-cd-env-injection-and-worker.md](./b5-cd-env-injection-and-worker.md) | CD への AUTHCORE_* 注入 / Solid Queue worker / ドキュメント更新 | 完了 |
| [b6-auth-e2e-smoke.md](./b6-auth-e2e-smoke.md) | 認証 E2E 疎通テスト | 完了 |

## 個別タスク

| ファイル | 概要 | ステータス |
|---|---|---|
| [docs-overhaul.md](./docs-overhaul.md) | README / CLAUDE.md / docs/tasks の横断ドキュメントリファクタ | 進行中（本タスク） |
| [prod-action-cable-solid-adapter-and-origins.md](./prod-action-cable-solid-adapter-and-origins.md) | production の ActionCable を Solid Cable + 非ブラウザ許可に揃える | 完了 |
| [qr-payment-foundation-mpm/](./qr-payment-foundation-mpm/) | QR 決済基盤 (MPM) MVP（STEP 01〜07、03 までマージ済み） | 進行中 |
| [server-bank-22-recipient-resolution-api.md](./server-bank-22-recipient-resolution-api.md) | 送金先検索 API（`GET /users/search?q=xxx`、表示名 ILIKE 部分一致）— クライアント送金機能 (`fuju-bank-app#client-bank-22`) のブロッカー解消 | 進行中（pg_trgm / AuditLog / rack-attack / icon_url / backfill は別タスク） |
| [server-bank-23-transfer-mfa-verify-flow.md](./server-bank-23-transfer-mfa-verify-flow.md) | 送金時 MFA 解消経路の仕様確定（AuthCore `POST /v1/auth/mfa/step-up` 新設候補） | 仕様確認済み（bank-backend 0 行変更、AuthCore 実装待ち） |

## 削除済み（履歴のみ Git ログから復元可能）

- `00-overview.md` 〜 `25-auth-policy-application.md`（MVP 計画 + AuthCore 連携、消化済み）
- `dedupe-test-ci-on-release-pr.md`
- `qr-payment-foundation-mpm.md`（スタブ。中身は `qr-payment-foundation-mpm/` ディレクトリへ移動済み）
- `update-readme-with-domain-overview.md`（消化済み、本タスク docs-overhaul で後続）
