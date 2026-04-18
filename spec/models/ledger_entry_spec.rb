require "rails_helper"

RSpec.describe LedgerEntry, type: :model do
  describe "validations" do
    it "amount が正の整数なら valid" do
      expect(build(:ledger_entry, amount: 100)).to be_valid
    end

    it "amount が負の整数なら valid" do
      expect(build(:ledger_entry, amount: -100)).to be_valid
    end

    it "amount=0 は invalid" do
      entry = build(:ledger_entry, amount: 0)
      expect(entry).not_to be_valid
      expect(entry.errors[:amount]).to be_present
    end

    it "amount が非整数は invalid" do
      entry = build(:ledger_entry, amount: 1.5)
      expect(entry).not_to be_valid
      expect(entry.errors[:amount]).to be_present
    end

    it "ledger_transaction が nil は invalid" do
      entry = build(:ledger_entry, ledger_transaction: nil)
      expect(entry).not_to be_valid
      expect(entry.errors[:ledger_transaction]).to be_present
    end

    it "account が nil は invalid" do
      entry = build(:ledger_entry, account: nil)
      expect(entry).not_to be_valid
      expect(entry.errors[:account]).to be_present
    end
  end
end
