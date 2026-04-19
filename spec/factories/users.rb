FactoryBot.define do
  factory :user do
    # ULID は Crockford Base32 (0-9A-HJKMNP-TV-Z) の 26 文字。
    # テストでは一意であればよいので、sequence の数値を 26 桁ゼロ埋めした文字列を使う。
    sequence(:external_user_id) { |n| n.to_s.rjust(26, "0") }
    sequence(:name) { |n| "User #{n}" }
  end
end
