require "rails_helper"

RSpec.describe Account, type: :model do
  describe "validations" do
    it "kind=user かつ user あり / balance_fuju=0 は valid" do
      user = create(:user)
      expect(user.account).to be_valid
    end

    it "kind=user かつ user_id=nil は invalid" do
      account = build(:account, kind: "user", user: nil)
      expect(account).not_to be_valid
      expect(account.errors[:user_id]).to be_present
    end

    it "kind=user かつ store が存在する場合は invalid" do
      store = create(:store)
      account = build(:account, kind: "user", user: create(:user), store: store)
      expect(account).not_to be_valid
      expect(account.errors[:store_id]).to be_present
    end

    it "kind=system_issuance かつ user が存在する場合は invalid" do
      user = create(:user)
      account = build(:account, :system_issuance, user: user)
      expect(account).not_to be_valid
      expect(account.errors[:user_id]).to be_present
    end

    it "kind=system_issuance かつ user=nil は valid" do
      account = build(:account, :system_issuance)
      expect(account).to be_valid
    end

    it "kind=system_issuance かつ store が存在する場合は invalid" do
      store = create(:store)
      account = build(:account, :system_issuance, store: store)
      expect(account).not_to be_valid
      expect(account.errors[:store_id]).to be_present
    end

    it "kind=store かつ store あり / user=nil / balance_fuju=0 は valid" do
      account = build(:account, :store)
      expect(account).to be_valid
    end

    it "kind=store かつ store=nil は invalid" do
      account = build(:account, :store, store: nil)
      expect(account).not_to be_valid
      expect(account.errors[:store_id]).to be_present
    end

    it "kind=store かつ user が存在する場合は invalid" do
      user = create(:user)
      account = build(:account, :store, user: user)
      expect(account).not_to be_valid
      expect(account.errors[:user_id]).to be_present
    end

    it "kind が KINDS 外の値は invalid" do
      account = build(:account, kind: "unknown")
      expect(account).not_to be_valid
      expect(account.errors[:kind]).to be_present
    end

    it "kind=user で balance_fuju<0 は model validation で invalid" do
      user = create(:user)
      user.account.balance_fuju = -1
      expect(user.account).not_to be_valid
      expect(user.account.errors[:balance_fuju]).to be_present
    end

    it "kind=store で balance_fuju<0 は model validation で invalid" do
      account = build(:account, :store, balance_fuju: -1)
      expect(account).not_to be_valid
      expect(account.errors[:balance_fuju]).to be_present
    end

    it "kind=system_issuance は balance_fuju<0 でも valid（発行原資）" do
      account = build(:account, :system_issuance, balance_fuju: -1_000)
      expect(account).to be_valid
    end

    it "kind=store で balance_fuju<0 を DB に保存しようとすると CHECK 制約で弾かれる" do
      account = create(:account, :store)
      expect do
        account.update_columns(balance_fuju: -1) # rubocop:disable Rails/SkipsModelValidations
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe ".system_issuance!" do
    context "system_issuance 口座が存在するとき" do
      let!(:system_account) { create(:account, :system_issuance) }

      it "system_issuance 口座を返す" do
        expect(Account.system_issuance!).to eq(system_account)
      end
    end

    context "system_issuance 口座が存在しないとき" do
      it "RecordNotFound 例外を投げる" do
        expect { Account.system_issuance! }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
