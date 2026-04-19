FactoryBot.define do
  factory :user do
    # 一意性だけ確保できればよく、実 ULID である必要はない
    sequence(:external_user_id) { |n| n.to_s.rjust(26, "0") }
    sequence(:name) { |n| "User #{n}" }
  end
end
