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

      it "25 文字だと invalid" do
        user = build(:user, external_user_id: "0" * 25)
        expect(user).not_to be_valid
        expect(user.errors[:external_user_id]).to be_present
      end

      it "27 文字だと invalid" do
        user = build(:user, external_user_id: "0" * 27)
        expect(user).not_to be_valid
        expect(user.errors[:external_user_id]).to be_present
      end

      it "小文字を含むと invalid（大文字のみ許容）" do
        user = build(:user, external_user_id: "01hzzzzzzzzzzzzzzzzzzzzzzz")
        expect(user).not_to be_valid
        expect(user.errors[:external_user_id]).to be_present
      end

      %w[I L O U].each do |forbidden|
        it "Crockford Base32 禁止文字 #{forbidden} を含むと invalid" do
          user = build(:user, external_user_id: forbidden * 26)
          expect(user).not_to be_valid
          expect(user.errors[:external_user_id]).to be_present
        end
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

    describe "public_id" do
      it "nil だと invalid（AuthCore 側で NOT NULL のため bank も必須）" do
        user = build(:user, public_id: nil)
        expect(user).not_to be_valid
        expect(user.errors[:public_id]).to be_present
      end

      it "英数字 + _- 3〜32 文字なら valid" do
        user = build(:user, public_id: "alice_01-AB")
        expect(user).to be_valid
      end

      it "下限ちょうど 3 文字なら valid（境界 inclusive）" do
        user = build(:user, public_id: "abc")
        expect(user).to be_valid
      end

      it "上限ちょうど 32 文字なら valid（境界 inclusive）" do
        user = build(:user, public_id: "a" * 32)
        expect(user).to be_valid
      end

      it "空文字は invalid" do
        user = build(:user, public_id: "")
        expect(user).not_to be_valid
        expect(user.errors[:public_id]).to be_present
      end

      it "2 文字だと invalid" do
        user = build(:user, public_id: "ab")
        expect(user).not_to be_valid
        expect(user.errors[:public_id]).to be_present
      end

      it "33 文字だと invalid" do
        user = build(:user, public_id: "a" * 33)
        expect(user).not_to be_valid
        expect(user.errors[:public_id]).to be_present
      end

      # `\A...\z` ではなく `^...$` 等への誤改修で改行を許容しないよう回帰防止
      ["alice\n", " alice", "alice ", "al ice"].each do |bad|
        it "空白・改行を含む #{bad.inspect} は invalid" do
          user = build(:user, public_id: bad)
          expect(user).not_to be_valid
          expect(user.errors[:public_id]).to be_present
        end
      end

      it "許可されない文字（マルチバイト）を含むと invalid" do
        user = build(:user, public_id: "アリス")
        expect(user).not_to be_valid
        expect(user.errors[:public_id]).to be_present
      end

      it "許可されない記号（@ 等）を含むと invalid" do
        user = build(:user, public_id: "alice@example")
        expect(user).not_to be_valid
        expect(user.errors[:public_id]).to be_present
      end

      it "同じ public_id を持つ 2 件目は uniqueness で invalid" do
        create(:user, public_id: "alice")
        duplicate = build(:user, public_id: "alice")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:public_id]).to be_present
      end

      # DB 層 NULL 許容を回帰テスト: 誤って users.public_id を NOT NULL 化すると
      # 本番 DB に残存しうる legacy NULL 行で ridgepole が落ちて deploy 不能になるため、
      # 「validation を bypass すれば NULL 行を作れる」= DB 制約が NULL 許容、を spec で固定する。
      it "DB 層は NULL 許容（validate: false なら NULL public_id でも save できる）" do
        user = build(:user, public_id: nil)

        expect { user.save(validate: false) }.to change { User.count }.by(1)
        expect(user.reload.public_id).to be_nil
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
