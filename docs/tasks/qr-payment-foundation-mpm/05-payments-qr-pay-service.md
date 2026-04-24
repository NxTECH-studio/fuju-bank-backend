# STEP 05: `Payments::QrPay` Service Object を新規作成

- **前提 STEP**:
  - [`03-account-kind-store.md`](./03-account-kind-store.md)（store 口座が作れる）
  - [`04-qr-signer-verifier.md`](./04-qr-signer-verifier.md)（Verifier は Controller で使うが、Service 自体は Store と Account が前提）
- **次の STEP**: [`06-payments-qr-controller.md`](./06-payments-qr-controller.md)
- **全体像**: [`00-overview.md`](./00-overview.md)

## 目的

店舗口座宛の送金を実行する。内部で `Ledger::Transfer` と同等のロジックを踏み、`LedgerTransaction` + 2 つの `LedgerEntry` を作成する。

## 変更ファイル

- `app/services/payments/qr_pay.rb`（新規）
- `spec/services/payments/qr_pay_spec.rb`

## 作業内容

1. 入力: `from_user:`, `store:`, `amount:`, `idempotency_key:`, `memo: nil`, `metadata: {}`, `occurred_at: Time.current`
2. バリデーション: `amount` 正整数、`store.active?` である
3. 冪等性: `LedgerTransaction.find_by(idempotency_key:)` が存在すれば返す
4. `ActiveRecord::Base.transaction` 内で:
   - `from_user.account.lock!` と `store.account.lock!` を取得（**account.id 昇順で lock して A→B / B→A デッドロック回避**）
   - 残高不足なら `InsufficientBalanceError`
   - `LedgerTransaction` を `kind: "transfer"`, `memo:`, `metadata: metadata.merge("payment_kind" => "qr_mpm", "store_id" => store.id)` で生成
   - `entries.build(account: from_account, amount: -amount)` / `entries.build(account: store_account, amount: +amount)`
   - 各 `balance_fuju` を更新
5. トランザクション外で `Ledger::Notifier.broadcast_credits(tx)` を呼ぶ
   - 現行 Notifier は `user.nil? → skip` なので、store 口座側（user_id=NULL）には broadcast されない（期待挙動）
6. `rescue ActiveRecord::RecordNotUnique` は既存 `Ledger::Transfer` と同様のリカバリ

## 受け入れ基準

- 正常系: from_user の残高が減り、store の残高が増える。`LedgerTransaction` + 2 つの `LedgerEntry` が作られる
- 残高不足で `InsufficientBalanceError`、DB はロールバックされる
- 非 active 店舗で `ValidationFailedError`
- 同じ `idempotency_key` での再実行は新規作成されず既存 tx が返る

## テスト観点

- 正常系（残高・entries・metadata）
- 冪等性（同 key 2 回 → レコード数増加なし）
- 残高不足
- amount バリデーション（0 / 負 / 非 Integer）
- 非 active 店舗
- Notifier が `from_user` 側に broadcast しないこと（`user.nil?` は store 側で true だが from_user 側は credit ではなく debit なので元々 broadcast されない想定）※ Overview のリスク参照
