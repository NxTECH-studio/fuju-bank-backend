require "rails_helper"

RSpec.describe Artifact, type: :model do
  describe "validations" do
    it "physical（location_url なし）の場合は valid" do
      expect(build(:artifact)).to be_valid
    end

    it ":url trait（location_url あり）の場合は valid" do
      expect(build(:artifact, :url)).to be_valid
    end

    it "location_kind=url で location_url が nil の場合は invalid" do
      artifact = build(:artifact, location_kind: "url", location_url: nil)
      expect(artifact).not_to be_valid
      expect(artifact.errors[:location_url]).to be_present
    end

    it "location_kind=physical で location_url がある場合は invalid" do
      artifact = build(:artifact, location_kind: "physical", location_url: "https://example.com/art/1")
      expect(artifact).not_to be_valid
      expect(artifact.errors[:location_url]).to be_present
    end

    it "location_kind が LOCATION_KINDS 外の値は invalid" do
      artifact = build(:artifact, location_kind: "magical")
      expect(artifact).not_to be_valid
      expect(artifact.errors[:location_kind]).to be_present
    end

    it "location_kind が nil のときは invalid" do
      artifact = build(:artifact, location_kind: nil)
      expect(artifact).not_to be_valid
      expect(artifact.errors[:location_kind]).to be_present
    end

    it "title が空のときは invalid" do
      artifact = build(:artifact, title: "")
      expect(artifact).not_to be_valid
      expect(artifact.errors[:title]).to be_present
    end

    it "user が nil のときは invalid" do
      artifact = build(:artifact, user: nil)
      expect(artifact).not_to be_valid
      expect(artifact.errors[:user]).to be_present
    end
  end

  describe "associations" do
    let!(:user) { create(:user) }
    let!(:artifact) { create(:artifact, user: user) }

    it "belongs_to :user" do
      expect(artifact.user).to eq(user)
    end
  end
end
