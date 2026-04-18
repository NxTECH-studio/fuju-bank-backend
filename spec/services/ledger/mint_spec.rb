require "rails_helper"

RSpec.describe Ledger::Mint do
  let!(:system_account) { create(:account, :system_issuance) }
  let!(:user) { create(:user) }
  let!(:artifact) { create(:artifact, user: user) }
  let!(:amount) { 100 }
  let!(:idempotency_key) { "mint-key-1" }
  let!(:metadata) { { dwell_seconds: 42 } }
  let!(:occurred_at) { Time.current }

  def default_params
    {
      artifact: artifact,
      user: user,
      amount: amount,
      idempotency_key: idempotency_key,
      metadata: metadata,
      occurred_at: occurred_at,
    }
  end

  def call!(**overrides)
    described_class.call(**default_params, **overrides)
  end

  describe ".call" do
    context "正常系" do
      it "ユーザー残高が amount だけ増える" do
        expect { call! }.to change { user.account.reload.balance_fuju }.from(0).to(amount)
      end

      it "system_issuance 残高が amount だけ減る（負値 OK）" do
        expect { call! }.to change { system_account.reload.balance_fuju }.from(0).to(-amount)
      end

      it "LedgerTransaction が 1 件作成され、entries は 2 件で SUM=0" do
        expect { call! }.to change { LedgerTransaction.count }.by(1)
        tx = LedgerTransaction.last
        expect(tx.kind).to eq("mint")
        expect(tx.artifact_id).to eq(artifact.id)
        expect(tx.idempotency_key).to eq(idempotency_key)
        expect(tx.entries.count).to eq(2)
        expect(tx.entries.sum(:amount)).to eq(0)
      end

      it "metadata / occurred_at が保存される" do
        travel_to Time.zone.local(2026, 4, 18, 12, 0, 0) do
          tx = call!(occurred_at: Time.current)
          expect(tx.metadata).to eq("dwell_seconds" => 42)
          expect(tx.occurred_at).to eq(Time.current)
        end
      end

      it "戻り値は作成された LedgerTransaction" do
        tx = call!
        expect(tx).to be_a(LedgerTransaction)
        expect(tx.persisted?).to be true
      end
    end

    context "冪等性" do
      it "同一 idempotency_key を 2 回呼んでも作成は 1 回だけ" do
        first_tx = call!
        expect { call! }.not_to(change { LedgerTransaction.count })
        expect(call!).to eq(first_tx)
      end

      it "同一 idempotency_key の 2 回目で残高は再加算されない" do
        call!
        expect { call! }.not_to(change { user.account.reload.balance_fuju })
      end

      it "ActiveRecord::RecordNotUnique が飛んだ場合は既存 transaction を返す" do
        existing = call!
        # 1 回目の find_by を nil にして save! 経路へ入らせ、save! は RecordNotUnique を raise、
        # rescue 後の find_by! が既存を返すことを検証する。
        allow(LedgerTransaction).to receive(:find_by).and_wrap_original do |_original, *_args|
          allow(LedgerTransaction).to receive(:find_by).and_call_original
          nil
        end
        allow(LedgerTransaction).to receive(:new).and_wrap_original do |original, **kwargs|
          tx = original.call(**kwargs)
          allow(tx).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("dup"))
          tx
        end

        expect(call!).to eq(existing)
      end
    end

    context "異常系" do
      [0, -10, 1.5].each do |bad_amount|
        it "amount=#{bad_amount} は ValidationFailedError を raise" do
          expect { call!(amount: bad_amount) }.to raise_error(ValidationFailedError) do |e|
            expect(e.code).to eq("VALIDATION_FAILED")
          end
        end
      end

      it "バリデーションエラー時は LedgerTransaction が保存されない" do
        expect do
          call!(amount: 0)
        rescue BankError
          nil
        end.not_to(change { LedgerTransaction.count })
      end
    end
  end
end
