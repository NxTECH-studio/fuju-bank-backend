require "rails_helper"

RSpec.describe Store, type: :model do
  describe "validations" do
    describe "code" do
      it "必須属性が揃えば valid" do
        store = build(:store)
        expect(store).to be_valid
      end

      it "nil のときは invalid" do
        store = build(:store, code: nil)
        expect(store).not_to be_valid
        expect(store.errors[:code]).to be_present
      end

      it "空文字のときは invalid" do
        store = build(:store, code: "")
        expect(store).not_to be_valid
        expect(store.errors[:code]).to be_present
      end

      it "同じ code の 2 件目は uniqueness で invalid" do
        create(:store, code: "SHOP001")
        duplicate = build(:store, code: "SHOP001")
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
      store = Store.create!(code: "SHOP001", name: "Shop", signing_secret: SecureRandom.hex(32))
      expect(store.active).to be(true)
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

  describe "associations" do
    let!(:store) { create(:store) }

    it "紐付く account が無い場合 store.account は nil" do
      expect(store.account).to be_nil
    end
  end
end
