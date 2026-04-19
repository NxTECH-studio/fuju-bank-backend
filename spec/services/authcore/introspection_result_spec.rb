require "rails_helper"

RSpec.describe Authcore::IntrospectionResult do
  describe "#active?" do
    context "active が true の場合" do
      let!(:result) { described_class.new("active" => true) }

      it "true を返す" do
        expect(result).to be_active
      end
    end

    context "active が false の場合" do
      let!(:result) { described_class.new("active" => false) }

      it "false を返す" do
        expect(result).not_to be_active
      end
    end

    context "active が nil の場合" do
      let!(:result) { described_class.new({}) }

      it "false を返す" do
        expect(result).not_to be_active
      end
    end
  end

  describe "#mfa_verified?" do
    context "mfa_verified が true の場合" do
      let!(:result) { described_class.new("mfa_verified" => true) }

      it "true を返す" do
        expect(result).to be_mfa_verified
      end
    end

    context "mfa_verified が nil の場合" do
      let!(:result) { described_class.new({}) }

      it "false 相当として扱う" do
        expect(result).not_to be_mfa_verified
      end
    end
  end

  describe "属性の取得" do
    let!(:payload) do
      {
        "active" => true,
        "sub" => "01HXSUBULID",
        "client_id" => "bank-client",
        "username" => "alice",
        "token_type" => "access_token",
        "mfa_verified" => false,
        "aud" => "authcore",
        "exp" => 1_900_000_000,
        "iat" => 1_800_000_000,
      }
    end
    let!(:result) { described_class.new(payload) }

    it "各属性が読み取れる" do
      expect(result.sub).to eq("01HXSUBULID")
      expect(result.client_id).to eq("bank-client")
      expect(result.username).to eq("alice")
      expect(result.token_type).to eq("access_token")
      expect(result.aud).to eq("authcore")
      expect(result.exp).to eq(1_900_000_000)
      expect(result.iat).to eq(1_800_000_000)
    end
  end
end
