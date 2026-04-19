# frozen_string_literal: true

# AuthCore 設定。JWT 検証に使う公開鍵と、許容する audience / issuer を集約する。
module Authcore
  module_function

  def jwt_public_key
    pem = ENV.fetch("AUTHCORE_JWT_PUBLIC_KEY")
    OpenSSL::PKey::RSA.new(pem)
  end

  def expected_audience
    ENV.fetch("AUTHCORE_EXPECTED_AUDIENCE", "authcore")
  end

  def expected_issuer
    ENV.fetch("AUTHCORE_EXPECTED_ISSUER", "authcore")
  end
end
