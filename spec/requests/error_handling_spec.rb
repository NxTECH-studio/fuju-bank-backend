require "rails_helper"

RSpec.describe "ErrorHandling", type: :request do
  before do
    Rails.application.routes.draw do
      get "/testing_errors/success" => "testing_errors#success"
      get "/testing_errors/not_found" => "testing_errors#not_found"
      get "/testing_errors/record_invalid" => "testing_errors#record_invalid"
      get "/testing_errors/insufficient_balance" => "testing_errors#insufficient_balance"
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
  end

  describe "BankError サブクラス" do
    it "InsufficientBalanceError の code / status が反映される" do
      get "/testing_errors/insufficient_balance"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(
        "error" => {
          "code" => "INSUFFICIENT_BALANCE",
          "message" => "残高が不足しています",
        },
      )
    end
  end

  describe "StandardError (非 development 環境)" do
    it "500 で INTERNAL_ERROR を返す" do
      get "/testing_errors/boom"

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body).to eq(
        "error" => {
          "code" => "INTERNAL_ERROR",
          "message" => "内部エラーが発生しました",
        },
      )
    end

    it "ApplicationController に StandardError の rescue_handler が登録されている" do
      handled = ApplicationController.rescue_handlers.map(&:first)
      expect(handled).to include("StandardError")
    end
  end
end
