# User → User のふじゅ〜送金を処理する Service Object。
# 残高不足の場合は InsufficientBalanceError を raise し、トランザクション全体を rollback する。
class Ledger::Transfer
  # @param from_user [User]
  # @param to_user [User]
  # @param amount [Integer] 正の整数
  # @param idempotency_key [String]
  # @param memo [String, nil] 表示用の任意メモ
  # @param metadata [Hash]
  # @param occurred_at [Time]
  # @return [LedgerTransaction]
  def self.call(**)
    new(**).call
  end

  def initialize(from_user:, to_user:, amount:, idempotency_key:, memo: nil, metadata: {}, occurred_at: Time.current)
    @from_user = from_user
    @to_user = to_user
    @amount = amount
    @idempotency_key = idempotency_key
    @memo = memo
    @metadata = metadata
    @occurred_at = occurred_at
  end

  def call
    raise ValidationFailedError.new(message: "amount must be positive integer") unless positive_integer?(@amount)
    raise ValidationFailedError.new(message: "cannot transfer to self") if @from_user.id == @to_user.id

    existing = LedgerTransaction.find_by(idempotency_key: @idempotency_key)
    return existing if existing

    tx = ActiveRecord::Base.transaction do
      # TODO: 本番規模ではデッドロック回避のため account.id 昇順で lock! すること（A→B と B→A の同時送金対策）。
      from_account = @from_user.account.lock!
      to_account = @to_user.account.lock!

      raise InsufficientBalanceError.new if from_account.balance_fuju < @amount

      tx = LedgerTransaction.new(
        kind: "transfer",
        idempotency_key: @idempotency_key,
        memo: @memo,
        metadata: @metadata,
        occurred_at: @occurred_at,
      )
      tx.entries.build(account: from_account, amount: -@amount)
      tx.entries.build(account: to_account, amount: @amount)
      tx.save!

      from_account.update!(balance_fuju: from_account.balance_fuju - @amount)
      to_account.update!(balance_fuju: to_account.balance_fuju + @amount)

      tx
    end
    Ledger::Notifier.broadcast_credits(tx)
    tx
  rescue ActiveRecord::RecordNotUnique
    # idempotency_key 以外の unique 制約違反まで吸収しないよう、既存が見つからなければ再 raise する。
    existing = LedgerTransaction.find_by(idempotency_key: @idempotency_key)
    raise if existing.nil?

    existing
  end

  private

  def positive_integer?(value)
    value.is_a?(Integer) && value > 0
  end
end
