require "spec_helper"
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"

raise "The Rails environment is running in production mode!" if Rails.env.production?

require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").each { |f| require f }

# AuthCore の公開鍵をテスト用キーペアに差し替えてから Rails を触る。
ENV["AUTHCORE_JWT_PUBLIC_KEY"] = TestKeypair.public_key_pem
# introspection 関連の env。Authcore モジュールは最初の参照で値をメモ化するため、
# Rails ロード前にグローバルで設定してテスト全体で一貫させる。
ENV["AUTHCORE_BASE_URL"] ||= "https://auth.fuju.example"
ENV["AUTHCORE_CLIENT_ID"] ||= "bank-client"
ENV["AUTHCORE_CLIENT_SECRET"] ||= "s3cret"

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include AuthHelpers, type: :request
  config.include AuthenticatedRequest, type: :request
  config.include IntrospectionStubs, type: :request
end
