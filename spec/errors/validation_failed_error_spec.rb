require "rails_helper"

RSpec.describe ValidationFailedError do
  it "BankError を継承している" do
    expect(described_class.ancestors).to include(BankError)
  end

  it "code / http_status のデフォルトが設定される" do
    error = described_class.new(message: "field is invalid")

    expect(error.code).to eq("VALIDATION_FAILED")
    expect(error.message).to eq("field is invalid")
    expect(error.http_status).to eq(:bad_request)
  end

  it "message を省略すると ArgumentError を返す" do
    expect { described_class.new }.to raise_error(ArgumentError)
  end
end
