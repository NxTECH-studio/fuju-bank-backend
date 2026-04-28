require "rails_helper"
require "yaml"

RSpec.describe "config/cable.yml" do # rubocop:disable RSpec/DescribeClass
  let!(:config) do
    path = Rails.root.join("config/cable.yml")
    YAML.safe_load(ERB.new(path.read).result, aliases: true, permitted_classes: [Symbol])
  end

  describe "production" do
    let!(:production) { config.fetch("production") }

    it "uses the solid_cable adapter" do
      expect(production["adapter"]).to eq("solid_cable")
    end

    it "writes pubsub messages to the primary database (相乗り構成)" do
      expect(production.dig("connects_to", "database", "writing")).to eq("primary")
    end

    it "configures polling_interval and message_retention" do
      expect(production["polling_interval"]).to be_present
      expect(production["message_retention"]).to be_present
    end
  end

  describe "non-production" do
    it "keeps the async adapter for development" do
      expect(config.dig("development", "adapter")).to eq("async")
    end

    it "keeps the test adapter for test" do
      expect(config.dig("test", "adapter")).to eq("test")
    end
  end
end
