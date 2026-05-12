require "rails_helper"

RSpec.describe UserProvisioner do
  let!(:external_user_id) { "01HYZ0000000000000000000AA" }

  describe ".call" do
    context "新規作成" do
      # public_id は AuthCore 側で NOT NULL のため bank 側でも presence 必須。
      # 新規作成系は呼び出し側 (POST /users/me) が必ず public_id を渡す契約。
      let!(:public_id) { "user_alice" }

      it "User を 1 件作成する" do
        expect { described_class.call(external_user_id: external_user_id, public_id: public_id) }
          .to change { User.count }.by(1)
      end

      it "Account(kind: 'user') を同時に作成する" do
        expect { described_class.call(external_user_id: external_user_id, public_id: public_id) }
          .to change { Account.where(kind: "user").count }.by(1)
      end

      it "作成された User の external_user_id は引数の値" do
        user = described_class.call(external_user_id: external_user_id, public_id: public_id)
        expect(user.external_user_id).to eq(external_user_id)
      end

      it "name 未指定の場合は nil で作成される" do
        user = described_class.call(external_user_id: external_user_id, public_id: public_id)
        expect(user.name).to be_nil
      end

      it "name / public_key を指定した場合、その値で作成される" do
        user = described_class.call(external_user_id: external_user_id, name: "Alice", public_key: "pk_abc", public_id: public_id)
        expect(user).to have_attributes(name: "Alice", public_key: "pk_abc")
      end

      it "public_id を指定した場合、その値で作成される" do
        user = described_class.call(external_user_id: external_user_id, public_id: "alice")
        expect(user.public_id).to eq("alice")
      end

      it "public_id 未指定だと presence validation で RecordInvalid を raise する" do
        expect { described_class.call(external_user_id: external_user_id) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end

      it "作成された Account の balance_fuju は 0" do
        user = described_class.call(external_user_id: external_user_id, public_id: public_id)
        expect(user.account.balance_fuju).to eq(0)
      end

      it "戻り値の previously_new_record? は true" do
        user = described_class.call(external_user_id: external_user_id, public_id: public_id)
        expect(user.previously_new_record?).to be(true)
      end
    end

    context "既存取得" do
      let!(:existing_user) { create(:user, external_user_id: external_user_id, name: "Original", public_key: "pk_original", public_id: "original_pid") }

      it "レコードは増えない" do
        expect { described_class.call(external_user_id: external_user_id) }
          .not_to(change { User.count })
      end

      it "既存の User を返す" do
        expect(described_class.call(external_user_id: external_user_id)).to eq(existing_user)
      end

      it "public_id を渡せば既存値が上書きされる（AuthCore 側 public_id 変更を bank へ伝播）" do
        described_class.call(external_user_id: external_user_id, public_id: "updated_pid")
        expect(existing_user.reload.public_id).to eq("updated_pid")
      end

      it "public_id が nil の場合は既存値を維持する" do
        described_class.call(external_user_id: external_user_id, public_id: nil)
        expect(existing_user.reload.public_id).to eq("original_pid")
      end

      it "同じ public_id を渡しても updated_at が動かない（no-op）" do
        travel_to(2.days.from_now) do
          expect { described_class.call(external_user_id: external_user_id, public_id: "original_pid") }
            .not_to(change { existing_user.reload.updated_at })
        end
      end

      it "name / public_key を渡しても既存属性は更新されない（最小 C スコープ: public_id のみ更新）" do
        described_class.call(external_user_id: external_user_id, name: "Updated", public_key: "pk_updated")
        expect(existing_user.reload).to have_attributes(name: "Original", public_key: "pk_original")
      end

      it "戻り値の previously_new_record? は false" do
        user = described_class.call(external_user_id: external_user_id)
        expect(user.previously_new_record?).to be(false)
      end
    end

    context "public_id 衝突時の挙動" do
      let!(:other_user) { create(:user, public_id: "taken") }
      let!(:existing_user) { create(:user, external_user_id: external_user_id, public_id: "original_pid") }

      # AuthCore でユーザー Y がリネームしたが bank 側に古い所有者 X が残っているケース。
      # ここで raise すると Y の認証付き全 API が 5xx になるため、bank は同期を諦める。
      it "他ユーザーが先に保有している public_id を渡されたら同期を諦め、既存値のまま返す" do
        result = described_class.call(external_user_id: external_user_id, public_id: "taken")

        expect(result.public_id).to eq("original_pid")
        expect(existing_user.reload.public_id).to eq("original_pid")
      end
    end

    context "既存ユーザー更新時の format / length 違反" do
      let!(:existing_user) { create(:user, external_user_id: external_user_id, public_id: "original_pid") }

      # uniqueness 衝突だけは sync 諦めて既存値を返す（リネーム競合）。
      # format 違反はクライアントバグなので silently swallow せず 422 として伝播させたい。
      it "形式違反の public_id を渡されたら RecordInvalid を伝播する（silent swallow しない）" do
        expect { described_class.call(external_user_id: external_user_id, public_id: "ab") }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(existing_user.reload.public_id).to eq("original_pid")
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
          described_class.call(external_user_id: external_user_id, public_id: "boom_user")
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
