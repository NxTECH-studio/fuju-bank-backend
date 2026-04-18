require "rails_helper"

RSpec.describe Ledger::Notifier do
  describe ".broadcast_credits" do
    context "mint transaction" do
      let!(:system_account) { create(:account, :system_issuance) }
      let!(:user) { create(:user) }
      let!(:artifact) { create(:artifact, user: user) }
      let!(:amount) { 150 }
      let!(:idempotency_key) { "notifier-mint-1" }
      let!(:occurred_at) { Time.zone.local(2026, 4, 18, 12, 0, 0) }
      let!(:tx) do
        Ledger::Mint.call(
          artifact: artifact,
          user: user,
          amount: amount,
          idempotency_key: idempotency_key,
          metadata: { dwell_seconds: 42 },
          occurred_at: occurred_at,
        )
      end

      it "受け手 User に UserChannel へ 1 回 broadcast する" do
        expect do
          described_class.broadcast_credits(tx)
        end.to have_broadcasted_to(user).from_channel(UserChannel).once
      end

      it "payload が credit 仕様通り（mint: from_user_id=nil, artifact_id あり）" do
        expect { described_class.broadcast_credits(tx) }
          .to have_broadcasted_to(user).from_channel(UserChannel).with do |payload|
            expect(payload[:type]).to eq("credit")
            expect(payload[:amount]).to eq(amount)
            expect(payload[:transaction_id]).to eq(tx.id)
            expect(payload[:transaction_kind]).to eq("mint")
            expect(payload[:artifact_id]).to eq(artifact.id)
            expect(payload[:from_user_id]).to be_nil
            expect(payload[:metadata]).to eq("dwell_seconds" => 42)
            expect(payload[:occurred_at]).to eq(occurred_at.iso8601)
          end
      end
    end

    context "transfer transaction" do
      let!(:from_user) { create(:user) }
      let!(:to_user) { create(:user) }
      let!(:amount) { 80 }
      let!(:occurred_at) { Time.zone.local(2026, 4, 18, 13, 0, 0) }
      let!(:tx) do
        from_user.account.update!(balance_fuju: 500)
        Ledger::Transfer.call(
          from_user: from_user,
          to_user: to_user,
          amount: amount,
          idempotency_key: "notifier-transfer-1",
          memo: "thanks",
          metadata: { channel: "hud" },
          occurred_at: occurred_at,
        )
      end

      it "受け手 User のみに broadcast する" do
        expect do
          described_class.broadcast_credits(tx)
        end.to have_broadcasted_to(to_user).from_channel(UserChannel).once
      end

      it "送り手 User には broadcast されない" do
        expect do
          described_class.broadcast_credits(tx)
        end.not_to have_broadcasted_to(from_user).from_channel(UserChannel)
      end

      it "payload の from_user_id は送り手 user_id / transaction_kind=transfer / artifact_id=nil" do
        expect { described_class.broadcast_credits(tx) }
          .to have_broadcasted_to(to_user).from_channel(UserChannel).with do |payload|
            expect(payload[:type]).to eq("credit")
            expect(payload[:amount]).to eq(amount)
            expect(payload[:transaction_kind]).to eq("transfer")
            expect(payload[:artifact_id]).to be_nil
            expect(payload[:from_user_id]).to eq(from_user.id)
            expect(payload[:metadata]).to eq("channel" => "hud")
            expect(payload[:occurred_at]).to eq(occurred_at.iso8601)
          end
      end
    end

    context "credit entry の account に user がいない場合" do
      let!(:system_account) { create(:account, :system_issuance) }
      let!(:user) { create(:user) }
      let!(:artifact) { create(:artifact, user: user) }
      let!(:tx) do
        Ledger::Mint.call(
          artifact: artifact,
          user: user,
          amount: 100,
          idempotency_key: "notifier-guard-1",
        )
      end

      it "user_id=nil の account の entry は broadcast されない" do
        # credit_entry の account.user を nil に見せかけ、ガード節で skip されることを確認する。
        credit_entry = tx.entries.find { |e| e.amount > 0 }
        allow(credit_entry.account).to receive(:user).and_return(nil)
        allow(tx).to receive(:entries).and_return([credit_entry])

        expect do
          described_class.broadcast_credits(tx)
        end.not_to have_broadcasted_to(user).from_channel(UserChannel)
      end
    end
  end
end
