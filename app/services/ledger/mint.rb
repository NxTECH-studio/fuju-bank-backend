# ふじゅ〜の発行。system_issuance 口座から User 口座へ amount を移動する。
# Artifact → User への発行を複式簿記として記帳し、同一トランザクションで残高キャッシュを更新する。
class Ledger::Mint
  # @param artifact [Artifact]
  # @param user [User]
  # @param amount [Integer] 正の整数
  # @param idempotency_key [String]
  # @param metadata [Hash] 滞留秒数などの文脈情報
  # @param occurred_at [Time]
  # @return [LedgerTransaction]
  def self.call(**)
    new(**).call
  end

  def initialize(artifact:, user:, amount:, idempotency_key:, metadata: {}, occurred_at: Time.current)
    @artifact = artifact
    @user = user
    @amount = amount
    @idempotency_key = idempotency_key
    @metadata = metadata
    @occurred_at = occurred_at
  end

  def call
    raise ValidationFailedError.new(message: "amount must be positive integer") unless positive_integer?(@amount)

    existing = LedgerTransaction.find_by(idempotency_key: @idempotency_key)
    return existing if existing

    tx = ActiveRecord::Base.transaction do
      system_account = Account.system_issuance!.lock!
      user_account = @user.account.lock!

      tx = LedgerTransaction.new(
        kind: "mint",
        idempotency_key: @idempotency_key,
        artifact_id: @artifact.id,
        metadata: @metadata,
        occurred_at: @occurred_at,
      )
      tx.entries.build(account: system_account, amount: -@amount)
      tx.entries.build(account: user_account, amount: @amount)
      tx.save!

      system_account.update!(balance_fuju: system_account.balance_fuju - @amount)
      user_account.update!(balance_fuju: user_account.balance_fuju + @amount)

      tx
    end
    # broadcast は transaction の外で。Solid Cable の INSERT を本体 rollback に巻き込まないため。
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
