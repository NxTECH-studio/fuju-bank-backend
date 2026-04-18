FactoryBot.define do
  factory :ledger_transaction do
    kind { "mint" }
    sequence(:idempotency_key) { |n| "key-#{n}" }
    artifact
    occurred_at { Time.current }
    metadata { {} }

    trait :transfer do
      kind { "transfer" }
      artifact { nil }
    end
  end
end
