require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "name が空のときは invalid" do
      user = User.new(name: "")
      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end
  end

  describe "after_create bootstrap_account!" do
    let!(:user) { create(:user) }

    it "account を 1 件自動生成する" do
      expect(user.account).to be_present
    end

    it "生成された account の kind が user である" do
      expect(user.account.kind).to eq("user")
    end

    it "生成された account の balance_fuju が 0 である" do
      expect(user.account.balance_fuju).to eq(0)
    end
  end

  describe "#destroy" do
    let!(:user) { create(:user) }

    it "関連 account が残っていると例外になる" do
      expect { user.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end
end
