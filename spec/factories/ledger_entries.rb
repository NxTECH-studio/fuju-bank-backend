FactoryBot.define do
  factory :ledger_entry do
    ledger_transaction
    account
    amount { 1 }
  end
end
