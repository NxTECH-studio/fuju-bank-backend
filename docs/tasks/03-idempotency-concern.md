# 03: Idempotency-Key concern

> 依存: #01

## 概要

`Idempotency-Key` HTTP ヘッダ（または body 内 `idempotency_key`）を解釈する Controller concern を実装する。
`POST /ledger/mint` / `POST /ledger/transfer` で利用される。

## 背景・目的

- マイニング層との通信は不安定ネットワーク越しになるため、冪等性は必須。
- エンドポイントごとに同じヘッダ解釈を書くのは DRY 的に NG。concern に寄せる。

## 影響範囲

- **変更対象**:
  - `app/controllers/concerns/idempotent.rb`（新規）
  - `spec/support/idempotent_shared_examples.rb`（任意、共通 spec）
- **破壊的変更**: なし
- **外部層への影響**: ヘッダ契約の公開

## スキーマ変更

なし

## 実装ステップ

1. concern
   ```ruby
   # app/controllers/concerns/idempotent.rb
   #
   # Idempotency-Key ヘッダ（または request body の idempotency_key）を解釈する。
   # 使用側は idempotency_key! を呼ぶことで、未指定時は 400 エラーになる。
   module Idempotent
     extend ActiveSupport::Concern

     IDEMPOTENCY_HEADER = "Idempotency-Key".freeze
     MIN_LENGTH = 8
     MAX_LENGTH = 255

     # 値が無ければ BankError(VALIDATION_FAILED, 400) を raise する。
     def idempotency_key!
       key = request.headers[IDEMPOTENCY_HEADER].presence || params[:idempotency_key].presence
       raise BankError.new(code: "VALIDATION_FAILED", message: "Idempotency-Key is required", http_status: :bad_request) if key.blank?
       raise BankError.new(code: "VALIDATION_FAILED", message: "Idempotency-Key length invalid", http_status: :bad_request) unless valid_length?(key)

       key
     end

     private

     def valid_length?(key)
       key.length >= MIN_LENGTH && key.length <= MAX_LENGTH
     end
   end
   ```
2. spec
   ```ruby
   # spec/requests/idempotent_spec.rb（or #16 の spec で代替）
   # ヘッダあり / ヘッダなし / 長さ不正 の 3 パターンを検証
   ```

## テスト要件

- ヘッダ指定で `idempotency_key!` が値を返す
- body 指定（params）で値を返す（ヘッダがあればヘッダ優先）
- 未指定で 400 `VALIDATION_FAILED`
- 短すぎ / 長すぎで 400 `VALIDATION_FAILED`

## 技術的な補足

- `rescue_from BankError` は #01 で登録済みのため、`raise` するだけで適切な JSON レスポンスになる。
- 長さの下限 8 は UUID（36 文字）/ ULID（26 文字）を想定した安全な下限値。呼び出し側の要件が固まり次第調整。
- ヘッダ名は `Idempotency-Key`（Stripe / IETF draft 準拠）。
- concern 内での `request` / `params` 参照は controller mixed-in の前提。他の用途には使わない。

## 非スコープ

- 同一 key で payload が異なる場合の `IDEMPOTENCY_CONFLICT` 検出（MVP は `LedgerTransaction` 側の unique 制約に任せる。厳密化は将来）。
- 永続キャッシュ（Redis 等） → 不要（`ledger_transactions` 自体が記録）。

## 受け入れ基準

- [ ] `Idempotent` concern が実装され、`LedgerController` に include される
- [ ] ヘッダ / body / 未指定の各ケースが仕様通り
- [ ] RSpec / RuboCop が通る
