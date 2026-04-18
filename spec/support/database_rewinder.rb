RSpec.configure do |config|
  config.before(:suite) do
    # Rails 8.1 では ActiveRecord の autoload が遅延するため、
    # database_rewinder の Railtie (ActiveSupport.on_load :active_record) が
    # clean_all 時点で未発火となり @cleaners が nil のまま。明示的に init する。
    ActiveRecord::Base.connection_pool
    DatabaseRewinder.init unless DatabaseRewinder.instance_variable_defined?(:@cleaners)
    DatabaseRewinder.clean_all
  end

  config.after do
    DatabaseRewinder.clean
  end
end
