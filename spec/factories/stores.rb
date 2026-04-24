FactoryBot.define do
  factory :store do
    sequence(:code) { |n| "STORE#{n.to_s.rjust(6, '0')}" }
    sequence(:name) { |n| "Store #{n}" }
    signing_secret { SecureRandom.hex(32) }
    active { true }
  end
end
