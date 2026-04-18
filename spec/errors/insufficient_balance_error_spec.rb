require "rails_helper"

RSpec.describe InsufficientBalanceError do
  it "BankError を継承している" do
    expect(described_class.ancestors).to include(BankError)
  end

  it "デフォルト属性が設定される" do
    error = described_class.new

    expect(error.code).to eq("INSUFFICIENT_BALANCE")
    expect(error.message).to eq("残高が不足しています")
    expect(error.http_status).to eq(422)
  end

  it "メッセージを上書きできる" do
    error = described_class.new(message: "balance: 0")

    expect(error.message).to eq("balance: 0")
    expect(error.code).to eq("INSUFFICIENT_BALANCE")
  end
end
