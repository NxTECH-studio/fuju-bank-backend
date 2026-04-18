# 20: mint / transfer 時の credit broadcast フック

> 依存: #11, #12, #19

## 概要

`Ledger::Mint` / `Ledger::Transfer` が成功したあと、受け手 User の `UserChannel` に
`credit` ペイロードを broadcast する。

## 背景・目的

- 作家 HUD に「+15 ふじゅ〜」のプッシュを届ける核心機能。
- 送金・発行のドメインロジックと通知を分離するため、`Ledger::Notifier` のような共通コンポーネントに寄せる。

## 影響範囲

- **変更対象**:
  - `app/services/ledger/notifier.rb`（新規）
  - `app/services/ledger/mint.rb`（broadcast 呼び出しを追加）
  - `app/services/ledger/transfer.rb`（broadcast 呼び出しを追加）
  - `spec/services/ledger/notifier_spec.rb`（新規）
  - `spec/services/ledger/mint_spec.rb` / `transfer_spec.rb`（broadcast 発火の検証を追加）
- **破壊的変更**: なし
- **外部層への影響**: HUD への broadcast ペイロード仕様を公開

## スキーマ変更

なし

## 実装ステップ

1. `app/services/ledger/notifier.rb`
   ```ruby
   # 記帳イベントを UserChannel へ broadcast するユーティリティ。
   class Ledger::Notifier
     # @param ledger_transaction [LedgerTransaction]
     def self.broadcast_credits(ledger_transaction)
       new(ledger_transaction).broadcast_credits
     end

     def initialize(ledger_transaction)
       @tx = ledger_transaction
     end

     def broadcast_credits
       credit_entries.each do |entry|
         user = entry.account.user
         next if user.nil? # system_issuance 等は通知しない

         UserChannel.broadcast_to(user, payload_for(entry))
       end
     end

     private

     def credit_entries
       @tx.entries.select { |e| e.amount > 0 }
     end

     def payload_for(entry)
       {
         type: "credit",
         amount: entry.amount,
         transaction_id: @tx.id,
         transaction_kind: @tx.kind,
         artifact_id: @tx.artifact_id,
         from_user_id: from_user_id,
         metadata: @tx.metadata,
         occurred_at: @tx.occurred_at.iso8601,
       }
     end

     def from_user_id
       return nil unless @tx.transfer_kind?

       debit_entry = @tx.entries.find { |e| e.amount < 0 }
       debit_entry&.account&.user_id
     end
   end
   ```
2. `Ledger::Mint#call` / `Ledger::Transfer#call` の末尾（トランザクション **外**）で呼ぶ
   ```ruby
   # Ledger::Mint#call の末尾
   tx = ActiveRecord::Base.transaction do
     # ... 既存処理 ...
   end
   Ledger::Notifier.broadcast_credits(tx)
   tx
   ```
   → 既存の `ActiveRecord::Base.transaction do ... end` の返り値で受ける形に変更する。
3. spec
   - `UserChannel.broadcast_to` が呼ばれる（`have_broadcasted_to` matcher）
   - mint → 受け手 User に 1 回 broadcast
   - transfer → 受け手 User に 1 回 broadcast、送り手には無し
   - payload 形式の検証

## テスト要件

- `have_broadcasted_to(user).from_channel(UserChannel).with { |payload| ... }` を使う
- system_issuance 口座は user_id が nil なので broadcast されない
- broadcast 失敗時に DB が rollback **されない**（トランザクション外で実行するため）
  - 逆に broadcast 内でエラーが出ても記帳は確定することを spec で明示する

## 技術的な補足

- broadcast は **トランザクションの外** で実行する。理由:
  - Solid Cable の書き込みは別テーブルへの INSERT なので、本体 transaction 内に入れると rollback リスクに巻き込まれる
  - broadcast 失敗は記帳の成功を妨げるべきではない
- 失敗時はログに残すが raise はしない方針（ここは `rescue => e; Rails.logger.error(...)` を入れるかを spec で合意）。MVP では raise する（早期発見優先）。
- payload の `amount` は常に正（受け手視点）。送り手視点の `debit` は送らない（MVP）。
- `from_user_id` は transfer のみ設定。mint は常に nil。

## 非スコープ

- debit 通知（送り手への「支払い完了」通知） → 将来
- HUD ack / 再送 → 将来
- 外部 Webhook（SNS 層への通知） → 将来

## 受け入れ基準

- [ ] mint で受け手 User に 1 回 broadcast
- [ ] transfer で受け手 User のみに broadcast
- [ ] payload が `docs/tasks/00-overview.md` の仕様通り
- [ ] RSpec / RuboCop が通る
