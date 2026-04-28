require "rails_helper"

RSpec.describe "config/cable.yml" do # rubocop:disable RSpec/DescribeClass
  describe "production" do
    let!(:production) { Rails.application.config_for(:cable, env: "production") }

    it "uses the solid_cable adapter" do
      expect(production[:adapter]).to eq("solid_cable")
    end

    it "writes pubsub messages to the primary database (相乗り構成)" do
      expect(production.dig(:connects_to, :database, :writing)).to eq("primary")
    end

    it "passes a Solid Cable parseable polling_interval (e.g. '0.1.seconds')" do
      expect(production[:polling_interval]).to eq("0.1.seconds")
    end

    it "passes a Solid Cable parseable message_retention (e.g. '1.day')" do
      expect(production[:message_retention]).to eq("1.day")
    end
  end

  describe "non-production" do
    it "keeps the async adapter for development" do
      expect(Rails.application.config_for(:cable, env: "development")[:adapter]).to eq("async")
    end

    it "keeps the test adapter for test" do
      expect(Rails.application.config_for(:cable, env: "test")[:adapter]).to eq("test")
    end
  end
end
