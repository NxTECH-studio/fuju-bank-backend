# STEP 04: `Qr::Signer` / `Qr::Verifier` を新規作成

- **前提 STEP**: [`02-store-model.md`](./02-store-model.md)（`Store` から `signing_secret` / `code` / `active` が参照できる）
- **次の STEP**: [`05-payments-qr-pay-service.md`](./05-payments-qr-pay-service.md)
- **全体像**: [`00-overview.md`](./00-overview.md)

> 備考: 03 の Account 変更はこの STEP と独立。04 と 03 は順不同で進めても良いが、05 に入る前に両方完了している必要がある。

## 目的

店舗コードを HMAC-SHA256 で署名・検証する純粋ロジック層。DB に触らないこと（Verifier は `Store` の検索だけ行う）。

## 変更ファイル

- `app/services/qr/signer.rb`（新規）
- `app/services/qr/verifier.rb`（新規）
- `spec/services/qr/signer_spec.rb`
- `spec/services/qr/verifier_spec.rb`

## 作業内容

1. `Qr::Signer.call(store:)` が `fuju://pay?store=<code>&sig=<hex>` を返す
   - `sig = OpenSSL::HMAC.hexdigest("SHA256", store.signing_secret, store.code)`
2. `Qr::Verifier.call(store_code:, signature:)` が該当 `Store` を `code` で検索し、期待署名と `ActiveSupport::SecurityUtils.secure_compare` で比較
   - 不一致 / 店舗不在 / `active = false` → `ValidationFailedError` を raise
   - 成功時は `Store` を返す

## 受け入れ基準

- Signer で生成した署名を Verifier が受理する
- 改ざんされた署名 / 異なる `signing_secret` は拒否される
- `active = false` の店舗は拒否される

## テスト観点

- 正常系（生成 → 検証）
- タンパリング検知（1 文字変えただけで拒否）
- 非 active 店舗の拒否
- タイミング攻撃対策として `secure_compare` 使用を確認（コードレビュー観点）
