FactoryBot.define do
  factory :artifact do
    user
    sequence(:title) { |n| "Artifact #{n}" }
    location_kind { "physical" }
    location_url { nil }

    trait :url do
      location_kind { "url" }
      location_url { "https://example.com/art/1" }
    end
  end
end
