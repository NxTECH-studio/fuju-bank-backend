FactoryBot.define do
  factory :user do
    # 一意性だけ確保できればよく、実 ULID である必要はない
    sequence(:external_user_id) { |n| n.to_s.rjust(26, "0") }
    sequence(:name) { |n| "User #{n}" }
    # public_id は AuthCore 側で一意保証されている前提なので、factory でも sequence で重複回避する。
    # User::PUBLIC_ID_REGEX に合致させるため英数 + `_` のみで構成する。
    sequence(:public_id) { |n| "user_#{n}" }
  end
end
