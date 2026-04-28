require "rails_helper"

RSpec.describe "config/environments/production.rb (Action Cable)" do # rubocop:disable RSpec/DescribeClass
  let!(:source) { Rails.root.join("config/environments/production.rb").read }

  it "allows the api.fujupay.app origin" do
    expect(source).to match(/config\.action_cable\.allowed_request_origins\s*=/)
    expect(source).to match(/api\\\.fujupay\\\.app/)
  end

  it "disables request forgery protection so native clients without Origin can connect" do
    expect(source).to match(/config\.action_cable\.disable_request_forgery_protection\s*=\s*true/)
  end
end
