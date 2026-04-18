require "rails_helper"

RSpec.describe "Idempotent", type: :request do
  before do
    Rails.application.routes.draw do
      get "/testing_idempotent" => "testing_idempotent#show"
      post "/testing_idempotent" => "testing_idempotent#show"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  let!(:valid_key) { "a" * 16 }

  describe "正常系" do
    it "Idempotency-Key ヘッダ指定で値を返す" do
      get "/testing_idempotent", headers: { "Idempotency-Key" => valid_key }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("idempotency_key" => valid_key)
    end

    it "body params の idempotency_key で値を返す" do
      post "/testing_idempotent", params: { idempotency_key: valid_key }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("idempotency_key" => valid_key)
    end

    it "ヘッダと body 両方ある場合はヘッダを優先する" do
      header_key = "h" * 16
      body_key = "b" * 16
      post "/testing_idempotent",
           params: { idempotency_key: body_key },
           headers: { "Idempotency-Key" => header_key }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("idempotency_key" => header_key)
    end
  end

  describe "異常系" do
    it "未指定で 400 VALIDATION_FAILED を返す" do
      get "/testing_idempotent"

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq(
        "error" => { "code" => "VALIDATION_FAILED", "message" => "Idempotency-Key is required" },
      )
    end

    it "空文字ヘッダで 400 VALIDATION_FAILED を返す" do
      get "/testing_idempotent", headers: { "Idempotency-Key" => "" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
      expect(response.parsed_body.dig("error", "message")).to eq("Idempotency-Key is required")
    end
  end

  describe "境界値" do
    it "8 文字（最小）で正常レスポンスを返す" do
      key = "a" * 8
      get "/testing_idempotent", headers: { "Idempotency-Key" => key }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("idempotency_key" => key)
    end

    it "7 文字で 400 VALIDATION_FAILED を返す" do
      get "/testing_idempotent", headers: { "Idempotency-Key" => "a" * 7 }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq(
        "error" => { "code" => "VALIDATION_FAILED", "message" => "Idempotency-Key length invalid" },
      )
    end

    it "255 文字（最大）で正常レスポンスを返す" do
      key = "a" * 255
      get "/testing_idempotent", headers: { "Idempotency-Key" => key }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("idempotency_key" => key)
    end

    it "256 文字で 400 VALIDATION_FAILED を返す" do
      get "/testing_idempotent", headers: { "Idempotency-Key" => "a" * 256 }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq(
        "error" => { "code" => "VALIDATION_FAILED", "message" => "Idempotency-Key length invalid" },
      )
    end
  end
end
