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
        allow_any_instance_of(User).to receive(:bootstrap_account!).and_raise(ActiveRecord::RecordInvalid)

        expect do
          described_class.call(external_user_id: external_user_id)
        rescue ActiveRecord::RecordInvalid
          nil
        end.not_to(change { User.count })
      end
    end

    context "並行作成" do
      it "RecordNotUnique を rescue して再 find し、既存 User を返す" do
        concurrent_user = create(:user, external_user_id: external_user_id)

        call_count = 0
        allow(User).to receive(:find_by).and_wrap_original do |original, *args|
          call_count += 1
          # 1 回目の find_by は nil を返して create! 経路へ進ませる
          call_count == 1 ? nil : original.call(*args)
        end
        allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("dup"))
        allow(User).to receive(:find_by!).and_wrap_original do |original, *args|
          original.call(*args)
        end

        expect(described_class.call(external_user_id: external_user_id)).to eq(concurrent_user)
      end
    end
  end
end
