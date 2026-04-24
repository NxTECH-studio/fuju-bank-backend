FactoryBot.define do
  factory :account do
    kind { "user" }
    user
    balance_fuju { 0 }

    trait :system_issuance do
      kind { "system_issuance" }
      user { nil }
    end

    trait :store do
      kind { "store" }
      user { nil }
      association :store, strategy: :create
    end
  end
end
