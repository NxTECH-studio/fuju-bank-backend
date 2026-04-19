require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    describe "external_user_id" do
      it "nil のときは invalid" do
        user = build(:user, external_user_id: nil)
        expect(user).not_to be_valid
        expect(user.errors[:external_user_id]).to be_present
      end

      it "ULID 形式でない文字列は invalid" do
        user = build(:user, external_user_id: "invalid")
        expect(user).not_to be_valid
        expect(user.errors[:external_user_id]).to be_present
      end

      it "I/L/O/U を含む 26 文字は Crockford Base32 違反で invalid" do
        user = build(:user, external_user_id: "I" * 26)
        expect(user).not_to be_valid
        expect(user.errors[:external_user_id]).to be_present
      end

      it "26 文字の Crockford Base32 文字列は valid" do
        user = build(:user, external_user_id: "01HZZZZZZZZZZZZZZZZZZZZZZZ")
        expect(user).to be_valid
      end

      it "同じ external_user_id を持つ 2 件目は uniqueness で invalid" do
        create(:user, external_user_id: "01HZZZZZZZZZZZZZZZZZZZZZZZ")
        duplicate = build(:user, external_user_id: "01HZZZZZZZZZZZZZZZZZZZZZZZ")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:external_user_id]).to be_present
      end
    end

    describe "name" do
      it "nil でも valid（lazy プロビジョニング想定）" do
        user = build(:user, name: nil)
        expect(user).to be_valid
      end
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
