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
| [users-search-by-public-id.md](./users-search-by-public-id.md) | `GET /users/search` を `public_id` 前方一致（大文字小文字無視）に切り替え（staging で空配列しか返らない問題の解消、AuthCore のハンドル世界観に整合） | 完了 |
| [users-search-cross-service-identity.md](./users-search-cross-service-identity.md) | `bank.users.public_id` がほぼ NULL で検索が空になる件の根本対処方針決定（A: eager fan-out / B: AuthCore へ委譲 / C: lazy 強化 / D: introspect 経由補完）→ B + 最小 C を採用、AuthCore 側 (`feature/users-search-by-public-id`) と bank 側 (`feat/users-search-authcore-delegation`) で実装中 | 実装中 |
| [server-bank-23-transfer-mfa-verify-flow.md](./server-bank-23-transfer-mfa-verify-flow.md) | 送金時 MFA 解消経路の仕様確定（AuthCore `POST /v1/auth/mfa/step-up` 新設候補） | 仕様確認済み（bank-backend コード変更 0 行、AuthCore 実装待ち） |
| [server-bank-24-transfer-accept-external-user-id.md](./server-bank-24-transfer-accept-external-user-id.md) | `POST /ledger/transfer` を external_user_id (ULID) 受け入れに揃え、`from_user_id` を JWT current_user に倒す（search → transfer 動線の繋ぎ込み、`UserResponse.sub` も同梱） | 未着手 |

## 削除済み（履歴のみ Git ログから復元可能）

- `00-overview.md` 〜 `25-auth-policy-application.md`（MVP 計画 + AuthCore 連携、消化済み）
- `dedupe-test-ci-on-release-pr.md`
- `qr-payment-foundation-mpm.md`（スタブ。中身は `qr-payment-foundation-mpm/` ディレクトリへ移動済み）
- `update-readme-with-domain-overview.md`（消化済み、本タスク docs-overhaul で後続）
