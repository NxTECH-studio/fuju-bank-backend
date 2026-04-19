# frozen_string_literal: true

# AuthCore 設定。JWT 検証に使う公開鍵と、許容する audience / issuer を集約する。
module Authcore
  module_function

  # 最初の参照時にのみ PEM をパースして保持する。リクエスト毎に OpenSSL::PKey::RSA.new を
  # 再実行すると RSA 鍵パースで数 ms のオーバーヘッドが乗るため。
  def jwt_public_key
    @jwt_public_key ||= OpenSSL::PKey::RSA.new(ENV.fetch("AUTHCORE_JWT_PUBLIC_KEY"))
  end

  def expected_audience
    @expected_audience ||= ENV.fetch("AUTHCORE_EXPECTED_AUDIENCE", "authcore")
  end

  def expected_issuer
    @expected_issuer ||= ENV.fetch("AUTHCORE_EXPECTED_ISSUER", "authcore")
  end

  def base_url
    ENV.fetch("AUTHCORE_BASE_URL")
  end

  def client_id
    ENV.fetch("AUTHCORE_CLIENT_ID")
  end

  def client_secret
    ENV.fetch("AUTHCORE_CLIENT_SECRET")
  end
end
