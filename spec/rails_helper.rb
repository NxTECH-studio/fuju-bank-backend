require "spec_helper"
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"

raise "The Rails environment is running in production mode!" if Rails.env.production?

require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").each { |f| require f }

# AuthCore の公開鍵をテスト用キーペアに差し替えてから Rails を触る。
ENV["AUTHCORE_JWT_PUBLIC_KEY"] = TestKeypair.public_key_pem

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include AuthHelpers, type: :request
  config.include AuthenticatedRequest, type: :request
end
