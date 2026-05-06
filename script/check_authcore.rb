#!/usr/bin/env ruby
# frozen_string_literal: true

# AuthCore 疎通確認スクリプト。
#
# register → login → introspect を 1 コマンドで実行し、bank の client_credentials が
# AuthCore に登録され、Introspection エンドポイントが期待通りに動くことを確認する。
#
# 使い方:
#   AUTHCORE_BASE_URL=https://authcore.fujupay.app \
#   AUTHCORE_CLIENT_ID=fuju-bank-backend \
#   AUTHCORE_CLIENT_SECRET=*** \
#     ruby script/check_authcore.rb
#
# 終了コード: 0=success / 1=failure

require "json"
require "net/http"
require "securerandom"
require "uri"

TIMEOUT_SECONDS = 5

# AuthCore に対し register → login → introspect を順に実行するチェッカー。
class AuthcoreCheck
  class CheckFailed < StandardError; end

  # 設定値の集約。env が欠けていれば即 CheckFailed。
  class Config
    attr_reader :base_uri, :client_id, :client_secret

    def self.load
      new(
        base_url: fetch_env("AUTHCORE_BASE_URL"),
        client_id: fetch_env("AUTHCORE_CLIENT_ID"),
        client_secret: fetch_env("AUTHCORE_CLIENT_SECRET"),
      )
    end

    def self.fetch_env(key)
      ENV.fetch(key) { raise CheckFailed.new("missing env var: #{key}") }
    end

    def initialize(base_url:, client_id:, client_secret:)
      @base_uri = URI.parse(base_url)
      @client_id = client_id
      @client_secret = client_secret
    end

    def basic_auth
      [client_id, client_secret]
    end
  end

  def initialize(config:)
    @config = config
  end

  def run
    log("setup", "base_url=#{@config.base_uri} client_id=#{@config.client_id}")
    credentials = register_test_user
    access_token = login(credentials)
    introspect(access_token)
    log("result", "OK")
  end

  private

  def register_test_user
    suffix = SecureRandom.hex(6)
    payload = {
      "email" => "check-authcore+#{suffix}@example.com",
      "password" => SecureRandom.base64(24),
      "public_id" => "chk#{suffix}",
    }
    status, body = post_json("/v1/auth/register", payload)
    expect_status!("register", status, body, expected: 201)
    log("register", "ok email=#{payload['email']}")
    payload
  end

  def login(credentials)
    status, body = post_json(
      "/v1/auth/login",
      {
        "identifier" => credentials.fetch("email"),
        "password" => credentials.fetch("password"),
      },
    )
    expect_status!("login", status, body, expected: 200)

    parsed = parse_json!(body, "login")
    raise CheckFailed.new("login returned MFA pre_token; this script does not support MFA users") if parsed["pre_token"]

    access_token = parsed["access_token"]
    raise CheckFailed.new("login response missing access_token: #{parsed.inspect}") if access_token.to_s.empty?

    log("login", "ok access_token=#{access_token[0, 12]}...")
    access_token
  end

  def introspect(access_token)
    status, body = post_form(
      "/v1/auth/introspect",
      { "token" => access_token, "token_type_hint" => "access_token" },
      basic_auth: @config.basic_auth,
    )
    expect_status!("introspect", status, body, expected: 200)

    parsed = parse_json!(body, "introspect")
    raise CheckFailed.new("introspect returned active=false: #{parsed.inspect}") unless parsed["active"] == true

    log("introspect", "ok active=true sub=#{parsed['sub']} aud=#{parsed['aud']} mfa_verified=#{parsed['mfa_verified']}")
    parsed
  end

  def post_json(path, payload)
    http_post(path, headers: { "Content-Type" => "application/json" }, body: JSON.generate(payload))
  end

  def post_form(path, form, basic_auth: nil)
    http_post(
      path,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(form),
      basic_auth: basic_auth,
    )
  end

  def http_post(path, headers:, body:, basic_auth: nil)
    uri = URI.join(@config.base_uri, path)
    req = Net::HTTP::Post.new(uri)
    headers.each { |k, v| req[k] = v }
    req.basic_auth(*basic_auth) if basic_auth
    req.body = body

    response = Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT_SECONDS,
      read_timeout: TIMEOUT_SECONDS,
    ) do |http|
      http.request(req)
    end

    [response.code.to_i, response.body]
  end

  def expect_status!(stage, status, body, expected:)
    return if status == expected

    raise CheckFailed.new("#{stage} failed: status=#{status} expected=#{expected} body=#{body}")
  end

  def parse_json!(body, stage)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise CheckFailed.new("[#{stage}] failed to parse JSON: #{e.message}: body=#{body.inspect}")
  end

  def log(stage, message)
    warn "[#{stage}] #{message}"
  end
end

begin
  AuthcoreCheck.new(config: AuthcoreCheck::Config.load).run
  exit 0
rescue AuthcoreCheck::CheckFailed => e
  warn "[result] NG: #{e.message}"
  exit 1
rescue StandardError => e
  warn "[result] NG: #{e.class}: #{e.message}"
  exit 1
end
