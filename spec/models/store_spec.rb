require "rails_helper"

RSpec.describe Store, type: :model do
  describe "validations" do
    it "必須属性が揃えば valid" do
      store = build(:store)
      expect(store).to be_valid
    end

    describe "code" do
      it "nil のときは invalid" do
        store = build(:store, code: nil)
        expect(store).not_to be_valid
        expect(store.errors[:code]).to be_present
      end

      it "同じ code の 2 件目は uniqueness で invalid" do
        existing = create(:store)
        duplicate = build(:store, code: existing.code)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:code]).to be_present
      end
    end

    describe "name" do
      it "nil のときは invalid" do
        store = build(:store, name: nil)
        expect(store).not_to be_valid
        expect(store.errors[:name]).to be_present
      end
    end

    describe "signing_secret" do
      it "nil のときは invalid" do
        store = build(:store, signing_secret: nil)
        expect(store).not_to be_valid
        expect(store.errors[:signing_secret]).to be_present
      end
    end
  end

  describe "defaults" do
    it "active はデフォルトで true" do
      expect(create(:store).active).to be(true)
    end
  end

  describe ".active" do
    let!(:active_store) { create(:store, active: true) }
    let!(:inactive_store) { create(:store, active: false) }

    it "active: true の store のみ返す" do
      expect(Store.active).to contain_exactly(active_store)
      expect(Store.active).not_to include(inactive_store)
    end
  end
end
