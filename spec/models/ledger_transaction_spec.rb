require "rails_helper"

RSpec.describe LedgerTransaction, type: :model do
  def build_tx(kind: "mint", artifact: nil, amounts: [1, -1], **attrs)
    tx_attrs = { kind: kind, occurred_at: Time.current }.merge(attrs)
    tx_attrs[:artifact] = kind == "mint" ? (artifact || create(:artifact)) : artifact
    tx = build(:ledger_transaction, **tx_attrs)
    amounts.each do |amount|
      account = amount.negative? ? create(:account, :system_issuance) : create(:user).account
      tx.entries.build(account: account, amount: amount)
    end
    tx
  end

  describe "validations" do
    it "kind=mint で artifact / entries が揃えば valid" do
      expect(build_tx(kind: "mint")).to be_valid
    end

    it "kind=transfer で artifact=nil / entries が揃えば valid" do
      expect(build_tx(kind: "transfer")).to be_valid
    end

    it "entries の SUM != 0 は invalid" do
      tx = build_tx(amounts: [2, -1])
      expect(tx).not_to be_valid
      expect(tx.errors[:entries]).to be_present
    end

    it "entries が 1 件以下の場合は invalid" do
      tx = build_tx(amounts: [1])
      expect(tx).not_to be_valid
      expect(tx.errors[:entries]).to be_present
    end

    it "idempotency_key 重複は invalid" do
      persisted = build_tx(idempotency_key: "dup-key")
      persisted.save!
      tx = build_tx(idempotency_key: "dup-key")
      expect(tx).not_to be_valid
      expect(tx.errors[:idempotency_key]).to be_present
    end

    it "kind=mint で artifact_id が nil の場合は invalid" do
      tx = build_tx(kind: "mint")
      tx.artifact = nil
      expect(tx).not_to be_valid
      expect(tx.errors[:artifact_id]).to be_present
    end

    it "kind=transfer で artifact_id がある場合は invalid" do
      tx = build_tx(kind: "transfer", artifact: create(:artifact))
      expect(tx).not_to be_valid
      expect(tx.errors[:artifact_id]).to be_present
    end

    it "kind が KINDS 外の値は invalid" do
      tx = build_tx
      tx.kind = "unknown"
      expect(tx).not_to be_valid
      expect(tx.errors[:kind]).to be_present
    end

    it "occurred_at が nil の場合は invalid" do
      tx = build_tx
      tx.occurred_at = nil
      expect(tx).not_to be_valid
      expect(tx.errors[:occurred_at]).to be_present
    end
  end

  describe "associations" do
    let!(:tx) { build_tx.tap(&:save!) }

    it "has_many :entries を持つ" do
      expect(tx.entries.count).to eq(2)
      expect(tx.entries.sum(:amount)).to eq(0)
    end
  end

  describe "#mint_kind? / #transfer_kind?" do
    it "kind=mint のときのみ mint_kind? が true" do
      expect(build(:ledger_transaction, kind: "mint").mint_kind?).to be true
      expect(build(:ledger_transaction, :transfer).mint_kind?).to be false
    end

    it "kind=transfer のときのみ transfer_kind? が true" do
      expect(build(:ledger_transaction, :transfer).transfer_kind?).to be true
      expect(build(:ledger_transaction, kind: "mint").transfer_kind?).to be false
    end
  end
end
