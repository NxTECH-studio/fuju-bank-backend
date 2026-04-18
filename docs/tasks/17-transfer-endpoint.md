# 17: POST /ledger/transfer エンドポイント

> 依存: #01, #03, #12

## 概要

User → User 送金 API。PayPay 的なユーザー間送金を提供する。

## 背景・目的

- User 同士でふじゅ〜をやり取りできると、作家コミュニティ内の価値循環が生まれる。
- べき等性は mint と同じ考え方で `Idempotency-Key` を必須にする。

## 影響範囲

- **変更対象**:
  - `config/routes.rb`
  - `app/controllers/ledger_controller.rb`（#16 で作成したものに `transfer` アクション追加）
  - `spec/requests/ledger_transfer_spec.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: 新規公開エンドポイント

## スキーマ変更

なし

## 実装ステップ

1. routes に追加
   ```ruby
   post "ledger/transfer", to: "ledger#transfer"
   ```
2. コントローラに `transfer` アクション追加
   ```ruby
   def transfer
     from_user = User.find(transfer_params[:from_user_id])
     to_user = User.find(transfer_params[:to_user_id])

     tx = Ledger::Transfer.call(
       from_user: from_user,
       to_user: to_user,
       amount: transfer_params[:amount].to_i,
       idempotency_key: idempotency_key!,
       memo: transfer_params[:memo],
       metadata: transfer_params[:metadata].to_h,
       occurred_at: parse_occurred_at(transfer_params[:occurred_at]),
     )

     render(json: serialize(tx), status: :ok)
   end

   private

   def transfer_params
     params.expect(ledger: [:from_user_id, :to_user_id, :amount, :memo, :occurred_at, metadata: {},])
   end
   ```
3. Request spec
   - 正常系: A→B に N、残高が正しく変化
   - 異常系: 残高不足 → 422 `INSUFFICIENT_BALANCE`
   - 異常系: `from_user_id == to_user_id` → 422 `VALIDATION_FAILED`
   - 冪等性: 同じ `Idempotency-Key` で 2 回 POST → 作成は 1 回
   - `Idempotency-Key` 未指定 → 400（#03 の concern）

## テスト要件

- 残高変動の精密テスト（送り手 -N、受け手 +N、system_issuance は変化なし）
- 残高不足時、`LedgerTransaction` が DB に保存されていないこと（rollback 検証）
- 冪等性
- エラーコード分類

## 技術的な補足

- `serialize` メソッドは #16 と共通化可能。コントローラ内 private メソッドとして共有する。
- `memo` は任意。payload の `metadata` とは別（`memo` は人間向け、`metadata` は機械向け）。
- 受け手側の broadcast は #20 で実装。

## 非スコープ

- 認証
- broadcast → #20
- 手数料（MVP は無し）

## 受け入れ基準

- [ ] 仕様通りに送金される
- [ ] 残高不足で 422 `INSUFFICIENT_BALANCE`
- [ ] 冪等性担保
- [ ] RSpec / RuboCop が通る
