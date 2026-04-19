require "rails_helper"

RSpec.describe UserProvisioner do
  let!(:external_user_id) { "01HYZ0000000000000000000AA" }

  describe ".call" do
    context "新規作成" do
      it "User を 1 件作成する" do
        expect { described_class.call(external_user_id: external_user_id) }
          .to change { User.count }.by(1)
      end

      it "Account(kind: 'user') を同時に作成する" do
        expect { described_class.call(external_user_id: external_user_id) }
          .to change { Account.where(kind: "user").count }.by(1)
      end

      it "作成された User の external_user_id は引数の値" do
        user = described_class.call(external_user_id: external_user_id)
        expect(user.external_user_id).to eq(external_user_id)
      end

      it "作成された User の name は nil" do
        user = described_class.call(external_user_id: external_user_id)
        expect(user.name).to be_nil
      end

      it "作成された Account の balance_fuju は 0" do
        user = described_class.call(external_user_id: external_user_id)
        expect(user.account.balance_fuju).to eq(0)
      end
    end

    context "既存取得" do
      let!(:existing_user) { create(:user, external_user_id: external_user_id) }

      it "レコードは増えない" do
        expect { described_class.call(external_user_id: external_user_id) }
          .not_to(change { User.count })
      end

      it "既存の User を返す" do
        expect(described_class.call(external_user_id: external_user_id)).to eq(existing_user)
      end
    end

    context "異常系" do
      it "不正な ULID は ActiveRecord::RecordInvalid を raise する" do
        expect { described_class.call(external_user_id: "not-a-ulid") }
          .to raise_error(ActiveRecord::RecordInvalid)
      end

      it "bootstrap_account! が失敗した場合、User も作成されない" do
        allow(User).to receive(:new).and_wrap_original do |original, **kwargs|
          user = original.call(**kwargs)
          allow(user).to receive(:bootstrap_account!).and_raise(StandardError, "account boom")
          user
        end

        expect do
          described_class.call(external_user_id: external_user_id)
        rescue StandardError
          nil
        end.not_to(change { User.count })
      end
    end

    context "並行作成" do
      it "RecordNotUnique を rescue して再 find し、既存 User を返す" do
        existing_other_tx_user = create(:user, external_user_id: external_user_id)

        # 1 回目の find_by は nil（create! 経路へ）、2 回目（rescue 後）は既存を返す
        allow(User).to receive(:find_by).and_return(nil, existing_other_tx_user)
        allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("dup"))

        expect(described_class.call(external_user_id: external_user_id)).to eq(existing_other_tx_user)
      end

      it "external_user_id 以外の unique 制約違反は再 raise する" do
        allow(User).to receive(:find_by).and_return(nil)
        allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("other unique"))

        expect { described_class.call(external_user_id: external_user_id) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end
end
