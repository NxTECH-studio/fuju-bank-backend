# QR決済基盤 (MPM) MVP 実装方針 — Overview

## 概要

店舗 → ユーザー方向の MPM（Merchant-Presented Mode）QR 決済基盤を MVP として構築する。
店舗は自身の QR を掲示し、ユーザーが HUD からスキャンして「ふじゅ〜」で支払う。
既存の `Ledger::Transfer` をベースに、店舗口座（Store Account）への送金として実装する。

本ファイルは全 STEP に共通する決定事項・全体像・既存コードとの整合性・リスクをまとめる。
個別の実装手順は `01` 〜 `07` の各 STEP ファイルを参照すること。

## STEP 一覧

| STEP | ファイル | 概要 |
| --- | --- | --- |
| 01 | [`01-schema-ridgepole.md`](./01-schema-ridgepole.md) | `db/Schemafile` に `stores` テーブルと `accounts.store_id` を追加 |
| 02 | [`02-store-model.md`](./02-store-model.md) | `Store` モデルを新規作成 |
| 03 | [`03-account-kind-store.md`](./03-account-kind-store.md) | `Account` モデルに `kind = 'store'` を追加 |
| 04 | [`04-qr-signer-verifier.md`](./04-qr-signer-verifier.md) | `Qr::Signer` / `Qr::Verifier` を新規作成 |
| 05 | [`05-payments-qr-pay-service.md`](./05-payments-qr-pay-service.md) | `Payments::QrPay` Service Object を新規作成 |
| 06 | [`06-payments-qr-controller.md`](./06-payments-qr-controller.md) | `POST /payments/qr` エンドポイントを追加 |
| 07 | [`07-manual-e2e.md`](./07-manual-e2e.md) | 動作確認（手動 E2E） |

基本順序: **DB → Model → Service（内側）→ Service（外側）→ Controller → Spec → 動作確認**。
各 STEP は「それ単体でコミット・PR できる」ことを目指している。

## 決定事項（ヒアリング結果まとめ）

| 項目 | 決定内容 |
| --- | --- |
| 方式 | **MPM 固定（static QR）**。CPM は将来対応。 |
| 店舗アカウント構造 | **A案: `stores` テーブル新設 + `accounts.kind = 'store'` + `accounts.store_id` を追加**。User 口座と同等の扱い。 |
| QR フォーマット | **URIスキーム方式** 例: `fuju://pay?store=<store_code>&sig=<hmac>` |
| QR の有効期限 | **無期限**（static QR。店舗停止時は `stores.active = false` で無効化） |
| 署名方式 | **HMAC-SHA256**。共有秘密鍵（per-store または system-wide）で店舗コードを署名し、改ざんを防止。 |
| 金額 | **ユーザーが HUD 上で指定**（static QR には金額を埋め込まない = 真の MPM 固定 QR） |
| Idempotency | 既存の `Idempotent` concern を流用（`Idempotency-Key` ヘッダ必須） |
| 認可 | 既存の `IntrospectionRequired` を流用。支払い実行は支払い元ユーザーの introspection を要求。 |
| 通知 | 既存の `Ledger::Notifier` + `UserChannel` を流用。支払い元ユーザーにも broadcast を拡張するかは別検討（下記リスクに記載）。 |

## 背景・目的

- 現状 `Ledger::Transfer` は User → User しか想定しておらず、店舗のような法人エンティティへの送金が行えない。
- fuju-bank のユースケース拡大のため、街中の店舗で「ふじゅ〜」を使って決済できる最小経路を用意する。
- 将来の CPM / 動的 QR / POS 連携の土台となるドメインモデル（Store / Store Account）を先に整える。

## 影響範囲（全体）

- **変更対象**:
  - `db/Schemafile` — `stores` テーブル追加 / `accounts` に `store_id` 追加 / `kind` CHECK 制約拡張
  - `app/models/store.rb`（新規）
  - `app/models/account.rb` — `kind = 'store'` 対応、`belongs_to :store, optional: true`
  - `app/services/qr/signer.rb`（新規） / `app/services/qr/verifier.rb`（新規）
  - `app/services/payments/qr_pay.rb`（新規）— 店舗宛送金の Service Object
  - `app/controllers/payments_controller.rb`（新規）
  - `config/routes.rb` — `POST /payments/qr` を追加
  - `app/services/ledger/notifier.rb` — `user.nil?` スキップのロジックは維持しつつ、store 口座向けの broadcast は行わない（現状動作と整合）
  - `spec/` 一式
- **破壊的変更**: なし。既存 `POST /ledger/transfer` の振る舞いは変更しない。`Account` の既存 `kind` 値（`system_issuance` / `user`）も保持。
- **外部層（マイニング / SNS）への影響**: なし。新エンドポイントは HUD（参照 UI 層）から直接叩かれる想定。

## スキーマ変更サマリ

詳細は [`01-schema-ridgepole.md`](./01-schema-ridgepole.md) を参照。

1. `stores` テーブル新設（`code` / `name` / `signing_secret` / `active` / `timestamps`、`code` に UNIQUE）
2. `accounts` に `store_id` 追加、`store_id IS NOT NULL` 部分ユニークインデックス
3. `balance_non_negative_for_user` CHECK 制約を `kind = 'system_issuance' OR balance_fuju >= 0` に置き換え

## テスト要件（横断）

- RSpec + FactoryBot を使用（プロジェクト方針通り）
- `let!` を優先（`RSpec/PreferLetBang`）
- specファイルは `app/` ミラー構造
- 新規 spec は `database_rewinder` による clean-up が効く前提で書く
- N+1 は bullet が検出するので、Notifier 呼び出しで warning が出ないこと

## 既存コードとの整合性

- **`Ledger::Transfer`**: 置き換えない。`Payments::QrPay` は別 Service として新設し、User→Store に特化したバリデーション（`store.active?` 等）を持たせる。将来リファクタで共通化するかは未決（下記参照）。
- **`accounts.kind` CHECK**: 既存制約の条件を `kind = 'system_issuance' OR balance >= 0` へ置き換える（store 口座も非負にするため）。既存の `system_issuance` 動作は不変。
- **`IntrospectionRequired`**: `Authcore::IntrospectionClient` が返す `sub` と `current_external_user_id` を比較する既存機構をそのまま利用。`PaymentsController` の `from_user_id` が introspection 主体と一致することを検証する必要があるため、`verify_introspection!` の枠組みで十分。
- **`Idempotent`**: 既存 concern をそのまま include する。`idempotency_key!` の仕様（8〜255 文字）は変更しない。
- **`Ledger::Notifier` / `UserChannel`**: 現行は `entry.account.user` が nil なら skip するため、store 口座向けのイベント漏れは無害に吸収される。ユーザー HUD 向けに「支払い成功イベント（debit）」を出すかは別判断（リスク参照）。
- **ApplicationController rescue_from**: `InsufficientBalanceError` / `ValidationFailedError` / `AuthenticationError` の HTTP ステータスマッピングは既存実装を踏襲する。新規エラーは追加しない方針。

## リスク・未決事項

1. **CPM（Consumer-Presented Mode）未対応**
   - ユーザーが QR を掲示して店舗がスキャンする方式は将来対応。
   - 今回のモデル設計（`stores` + `accounts.kind='store'`）は CPM 実装時にも流用可能な粒度にしている。

2. **動的 QR（金額埋め込み / トランザクション単位）未対応**
   - 金額はユーザー HUD で指定する static QR 固定。
   - 将来は `qr_tokens` テーブルなどを新設し、金額・有効期限・nonce を持たせる想定。

3. **store 側のリアルタイム通知未対応**
   - 現行 `Ledger::Notifier` は `user_id` にしか broadcast しない。店舗向け通知が必要になったら `StoreChannel` の新設を検討。
   - MVP では売上確認は別経路（ダッシュボード API 等）の想定で OK かを要確認。

4. **支払い元ユーザーへの debit 通知**
   - 現状 Notifier は credit（受取側）のみ broadcast する。
   - HUD で「支払い成功」を即時表示したい場合は Notifier 拡張（or 別 broadcast）の検討が必要。MVP スコープ外とする。

5. **`signing_secret` の保管**
   - 現状は `stores.signing_secret` に平文保存。将来的に Rails credentials か KMS 的な仕組みに退避することを想定。
   - MVP では DB カラムのままで進めるが、ログ出力除外（`filter_parameters`）の追加は実装時に検討する。

6. **`Payments::QrPay` と `Ledger::Transfer` の重複**
   - ロジックはほぼ同一。MVP では DRY より「店舗ドメインを独立して進化させやすいこと」を優先して別クラスにする。
   - 3 つ目の送金系が出てきた時点で共通化リファクタを検討する。

7. **店舗コードの命名規則**
   - ULID / 任意短縮文字列 / 運営発行の通し番号など、どれでも今回のスキーマは対応可能。決めは運用判断。MVP では「ユニークな文字列」以上の制約は入れない。
