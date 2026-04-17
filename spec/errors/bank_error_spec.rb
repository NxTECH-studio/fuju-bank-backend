require "rails_helper"

RSpec.describe BankError do
  it "code / message / http_status を保持する" do
    error = described_class.new(code: "SAMPLE", message: "テスト", http_status: 418)

    expect(error.code).to eq("SAMPLE")
    expect(error.message).to eq("テスト")
    expect(error.http_status).to eq(418)
  end

  it "http_status のデフォルトは 422" do
    error = described_class.new(code: "SAMPLE", message: "テスト")

    expect(error.http_status).to eq(422)
  end

  it "StandardError を継承している（rescue_from で補足可能）" do
    expect(described_class.ancestors).to include(StandardError)
  end
end
