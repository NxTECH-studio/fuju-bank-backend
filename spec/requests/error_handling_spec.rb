require "rails_helper"

RSpec.describe "ErrorHandling", type: :request do
  before do
    Rails.application.routes.draw do
      get "/testing_errors/success" => "testing_errors#success"
      get "/testing_errors/not_found" => "testing_errors#not_found"
      get "/testing_errors/record_invalid" => "testing_errors#record_invalid"
      get "/testing_errors/record_invalid_multiple" => "testing_errors#record_invalid_multiple"
      get "/testing_errors/insufficient_balance" => "testing_errors#insufficient_balance"
      get "/testing_errors/insufficient_balance_custom_message" => "testing_errors#insufficient_balance_custom_message"
      get "/testing_errors/bank_error_custom_status" => "testing_errors#bank_error_custom_status"
      get "/testing_errors/boom" => "testing_errors#boom"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  describe "正常系" do
    it "通常レスポンスは ErrorResponder の影響を受けない" do
      get "/testing_errors/success"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("ok" => true)
    end
  end

  describe "ActiveRecord::RecordNotFound" do
    it "404 で NOT_FOUND を返す" do
      get "/testing_errors/not_found"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq(
        "error" => { "code" => "NOT_FOUND", "message" => "record missing" },
      )
    end
  end

  describe "ActiveRecord::RecordInvalid" do
    it "422 で VALIDATION_FAILED を返し、errors.full_messages をメッセージに含める" do
      get "/testing_errors/record_invalid"

      expect(response).to have_http_status(:unprocessable_entity)
      parsed = response.parsed_body
      expect(parsed.dig("error", "code")).to eq("VALIDATION_FAILED")
      expect(parsed.dig("error", "message")).to include("is invalid")
    end

    it "複数 errors を ', ' 区切りで結合して返す" do
      get "/testing_errors/record_invalid_multiple"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to eq("Name is too short, Name can't be blank")
    end
  end

  describe "BankError" do
    it "InsufficientBalanceError のデフォルト code / status / message が反映される" do
      get "/testing_errors/insufficient_balance"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(
        "error" => {
          "code" => "INSUFFICIENT_BALANCE",
          "message" => "残高が不足しています",
        },
      )
    end

    it "InsufficientBalanceError のカスタム message が API レスポンスまで貫通する" do
      get "/testing_errors/insufficient_balance_custom_message"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to eq("balance: 0 JFY")
    end

    it "BankError の http_status 上書きが HTTP ステータスに反映される" do
      get "/testing_errors/bank_error_custom_status"

      expect(response).to have_http_status(418)
      expect(response.parsed_body).to eq(
        "error" => {
          "code" => "TEAPOT",
          "message" => "short and stout",
        },
      )
    end
  end

  describe "StandardError (非 development 環境)" do
    it "500 で INTERNAL_ERROR を返し、例外を Rails.logger.error に出力する" do
      allow(Rails.logger).to receive(:error)

      get "/testing_errors/boom"

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body).to eq(
        "error" => {
          "code" => "INTERNAL_ERROR",
          "message" => "内部エラーが発生しました",
        },
      )
      expect(Rails.logger).to have_received(:error).with(a_string_including("boom"))
    end
  end
end
