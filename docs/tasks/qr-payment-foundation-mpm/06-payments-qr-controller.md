# STEP 06: `POST /payments/qr` エンドポイントを追加

- **前提 STEP**:
  - [`04-qr-signer-verifier.md`](./04-qr-signer-verifier.md)（Verifier をコントローラから呼ぶ）
  - [`05-payments-qr-pay-service.md`](./05-payments-qr-pay-service.md)（Service 本体）
- **次の STEP**: [`07-manual-e2e.md`](./07-manual-e2e.md)
- **全体像**: [`00-overview.md`](./00-overview.md)

## 目的

HUD から QR 支払いを実行する HTTP 入り口を提供する。introspection と idempotency の枠組みを既存のまま踏襲する。

## 変更ファイル

- `config/routes.rb`
- `app/controllers/payments_controller.rb`（新規）
- `spec/requests/payments_spec.rb`（新規）

## 作業内容

1. ルート: `post "payments/qr", to: "payments#qr"`
2. コントローラは `IntrospectionRequired` と `Idempotent` を include
3. リクエスト body:
   ```json
   {
     "payment": {
       "from_user_id": 1,
       "store_code": "STORE_ABC",
       "signature": "<hex>",
       "amount": 100,
       "memo": "コーヒー代",
       "occurred_at": "2026-04-24T12:34:56Z",
       "metadata": {}
     }
   }
   ```
4. 処理フロー:
   - `from_user = User.find(params[:from_user_id])`
   - `store = Qr::Verifier.call(store_code:, signature:)` — 失敗時は ValidationFailedError
   - `Payments::QrPay.call(...)` を呼び、結果を `serialize_transaction` で返す（既存 LedgerController の serializer と同形で良い）
5. `parse_occurred_at` / `serialize_transaction` のヘルパーは LedgerController と重複するので、必要なら本 STEP の範囲で `ApplicationController` or concern へ切り出しても良い（本 MVP では重複許容でも可、判断は実装者）

## 受け入れ基準

- 正常系: 200 応答、body は `Ledger#transfer` と同形の tx JSON
- 署名不正で 400 (`VALIDATION_FAILED`)
- 残高不足で 422 相当（既存の `InsufficientBalanceError` と同じ HTTP ステータスを踏襲 — `app/controllers/application_controller.rb` の rescue_from 参照）
- `Idempotency-Key` 欠落で 400
- introspection 失敗（`sub` 不一致）で 401

## テスト観点

- request spec で各ステータスコードと body 形を確認
- 同 Idempotency-Key 2 回投げて冪等に動くこと
- FactoryBot で `store`, `from_user`, 初期残高を用意
