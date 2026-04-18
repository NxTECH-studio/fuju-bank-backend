# 18: GET /users/:id/transactions エンドポイント

> 依存: #01, #09, #11, #12

## 概要

特定 User の取引履歴（mint 受信 / transfer 送受信）を時系列で返す API。ページネーション対応。

## 背景・目的

- 作家 HUD / 管理画面から過去履歴を見るための API。
- mint と transfer を統合した「入出金履歴」のビューを提供する。

## 影響範囲

- **変更対象**:
  - `config/routes.rb`（#13 の `resources :users do resources :transactions end` を利用）
  - `app/controllers/user_transactions_controller.rb`（新規）
  - `spec/requests/user_transactions_spec.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: 新規エンドポイント

## スキーマ変更

なし

## 実装ステップ

1. routes は #13 で `resources :users do resources :transactions, only: [:index], controller: "user_transactions" end` を用意済み
2. コントローラ
   ```ruby
   # app/controllers/user_transactions_controller.rb
   # TODO: 認証は将来拡張
   class UserTransactionsController < ApplicationController
     DEFAULT_LIMIT = 50
     MAX_LIMIT = 200

     def index
       user = User.find(params[:user_id])
       limit = [[params[:limit].to_i, DEFAULT_LIMIT].max, MAX_LIMIT].min
       limit = DEFAULT_LIMIT if limit < 1

       entries = LedgerEntry
         .where(account_id: user.account.id)
         .includes(ledger_transaction: :artifact)
         .order(id: :desc)
         .limit(limit)

       render(json: { data: entries.map { |e| serialize(e, user) }, })
     end

     private

     def serialize(entry, user)
       tx = entry.ledger_transaction
       {
         entry_id: entry.id,
         transaction_id: tx.id,
         transaction_kind: tx.kind,
         direction: entry.amount > 0 ? "credit" : "debit",
         amount: entry.amount.abs,
         artifact_id: tx.artifact_id,
         counterparty_user_id: counterparty_user_id(tx, user),
         memo: tx.memo,
         metadata: tx.metadata,
         occurred_at: tx.occurred_at.iso8601,
         created_at: tx.created_at.iso8601,
       }
     end

     def counterparty_user_id(tx, user)
       return nil unless tx.transfer_kind?

       other_entry = tx.entries.find { |e| e.account_id != user.account.id }
       other_entry&.account&.user_id
     end
   end
   ```
3. Request spec
   - mint / transfer を混在させた履歴が取得できる
   - `direction` が正しい（credit / debit）
   - `limit` パラメータが効く
   - pagination: `limit` のデフォルト / 上限

## テスト要件

- 複合シナリオ: mint → transfer → transfer を発生させて履歴の順序と方向を検証
- N+1 検出: `includes(ledger_transaction: :artifact)` + `tx.entries.find` で bullet が鳴かないこと
- 空の履歴でも `data: []` を返す

## 技術的な補足

- `counterparty_user_id` の実装で `tx.entries.find { |e| ... }` を呼ぶと、事前 include していないと N+1 が出る。
  → `includes(ledger_transaction: { entries: :account })` にして bullet の警告を回避（実装時に調整）。
- ページネーションは cursor / offset いずれでも可。MVP は `limit` のみで十分。将来 `before_id` / `after_id` を追加。
- 返却フォーマットは `{ data: [...] }` のラッパーあり（件数が多いことを前提に一貫性のため）。

## 非スコープ

- 検索フィルタ（kind / 日付範囲） → 将来
- CSV エクスポート → 将来

## 受け入れ基準

- [ ] `GET /users/:id/transactions` が時系列で履歴を返す
- [ ] `direction` / `counterparty_user_id` が正しい
- [ ] bullet 警告なし
- [ ] RSpec / RuboCop が通る
