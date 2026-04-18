require "rails_helper"

RSpec.describe Ledger::Transfer do
  let!(:from_user) { create(:user) }
  let!(:to_user) { create(:user) }
  let!(:initial_balance) { 500 }
  let!(:amount) { 100 }
  let!(:idempotency_key) { "transfer-key-1" }
  let!(:memo) { "thanks" }
  let!(:metadata) { { channel: "hud" } }
  let!(:occurred_at) { Time.current }

  before do
    from_user.account.update!(balance_fuju: initial_balance)
  end

  def default_params
    {
      from_user: from_user,
      to_user: to_user,
      amount: amount,
      idempotency_key: idempotency_key,
      memo: memo,
      metadata: metadata,
      occurred_at: occurred_at,
    }
  end

  def call!(**overrides)
    described_class.call(**default_params, **overrides)
  end

  describe ".call" do
    context "正常系" do
      it "from_user 残高が amount だけ減る" do
        expect { call! }.to change { from_user.account.reload.balance_fuju }.from(initial_balance).to(initial_balance - amount)
      end

      it "to_user 残高が amount だけ増える" do
        expect { call! }.to change { to_user.account.reload.balance_fuju }.from(0).to(amount)
      end

      it "LedgerTransaction が 1 件作成され、kind=transfer / artifact_id=nil / entries 2 件 / SUM=0" do
        expect { call! }.to change { LedgerTransaction.count }.by(1)
        tx = LedgerTransaction.last
        expect(tx.kind).to eq("transfer")
        expect(tx.artifact_id).to be_nil
        expect(tx.idempotency_key).to eq(idempotency_key)
        expect(tx.entries.count).to eq(2)
        expect(tx.entries.sum(:amount)).to eq(0)
      end

      it "memo / metadata / occurred_at が保存される" do
        travel_to Time.zone.local(2026, 4, 18, 12, 0, 0) do
          tx = call!(occurred_at: Time.current)
          expect(tx.memo).to eq(memo)
          expect(tx.metadata).to eq("channel" => "hud")
          expect(tx.occurred_at).to eq(Time.current)
        end
      end

      it "戻り値は作成された LedgerTransaction" do
        tx = call!
        expect(tx).to be_a(LedgerTransaction)
        expect(tx.persisted?).to be true
      end

      it "残高ちょうどの amount でも成功し、from 残高は 0 になる" do
        expect { call!(amount: initial_balance) }.to change { from_user.account.reload.balance_fuju }.from(initial_balance).to(0)
      end

      it "occurred_at を渡さないと Time.current で保存される" do
        travel_to Time.zone.local(2026, 4, 18, 10, 0, 0) do
          tx = described_class.call(
            from_user: from_user,
            to_user: to_user,
            amount: amount,
            idempotency_key: "default-occurred-at-key",
          )
          expect(tx.occurred_at).to eq(Time.current)
        end
      end
    end

    context "冪等性" do
      it "同一 idempotency_key を 2 回呼んでも作成は 1 回だけ" do
        first_tx = call!
        expect { call! }.not_to(change { LedgerTransaction.count })
        expect(call!).to eq(first_tx)
      end

      it "同一 idempotency_key の 2 回目で残高は再移動されない" do
        call!
        expect { call! }.not_to(change { from_user.account.reload.balance_fuju })
        expect { call! }.not_to(change { to_user.account.reload.balance_fuju })
      end

      it "ActiveRecord::RecordNotUnique が飛んだ場合は既存 transaction を返す" do
        existing = call!
        allow(LedgerTransaction).to receive(:find_by).and_return(nil, existing)
        allow(LedgerTransaction).to receive(:new).and_wrap_original do |original, **kwargs|
          tx = original.call(**kwargs)
          allow(tx).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("dup"))
          tx
        end

        expect(call!).to eq(existing)
      end

      it "RecordNotUnique が idempotency_key 以外の理由で飛んだ場合は再 raise する" do
        allow(LedgerTransaction).to receive(:find_by).and_return(nil)
        allow(LedgerTransaction).to receive(:new).and_wrap_original do |original, **kwargs|
          tx = original.call(**kwargs)
          allow(tx).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("other unique"))
          tx
        end

        expect { call! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "異常系: 残高不足" do
      it "残高不足なら InsufficientBalanceError を raise" do
        expect { call!(amount: initial_balance + 1) }.to raise_error(InsufficientBalanceError) do |e|
          expect(e.code).to eq("INSUFFICIENT_BALANCE")
        end
      end

      it "残高不足で LedgerTransaction は保存されない" do
        expect do
          call!(amount: initial_balance + 1)
        rescue BankError
          nil
        end.not_to(change { LedgerTransaction.count })
      end

      it "残高不足で from/to の残高は変化しない" do
        expect do
          call!(amount: initial_balance + 1)
        rescue BankError
          nil
        end.not_to(change { [from_user.account.reload.balance_fuju, to_user.account.reload.balance_fuju] })
      end
    end

    context "異常系: 自己送金" do
      it "from_user == to_user なら ValidationFailedError を raise" do
        expect { call!(to_user: from_user) }.to raise_error(ValidationFailedError) do |e|
          expect(e.code).to eq("VALIDATION_FAILED")
        end
      end

      it "自己送金で LedgerTransaction は保存されない" do
        expect do
          call!(to_user: from_user)
        rescue BankError
          nil
        end.not_to(change { LedgerTransaction.count })
      end
    end

    context "異常系: amount" do
      [0, -10, 1.5, "100", nil].each do |bad_amount|
        it "amount=#{bad_amount.inspect} は ValidationFailedError を raise" do
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
