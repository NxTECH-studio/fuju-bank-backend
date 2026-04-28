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

REQUIRED_ENV = %w[AUTHCORE_BASE_URL AUTHCORE_CLIENT_ID AUTHCORE_CLIENT_SECRET].freeze

class CheckFailed < StandardError; end

def env!(key)
  ENV.fetch(key) { raise CheckFailed.new("missing env var: #{key}") }
end

def log(stage, message)
  warn "[#{stage}] #{message}"
end

def http_request(method:, path:, headers: {}, body: nil, basic_auth: nil)
  uri = URI.join(env!("AUTHCORE_BASE_URL"), path)
  klass = method == :post ? Net::HTTP::Post : Net::HTTP::Get
  req = klass.new(uri)
  headers.each { |k, v| req[k] = v }
  req.basic_auth(*basic_auth) if basic_auth
  req.body = body if body

  response = Net::HTTP.start(
    uri.hostname,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: TIMEOUT_SECONDS,
    read_timeout: TIMEOUT_SECONDS,
  ) do |http|
    http.request(req)
  end

  [response.code.to_i, response.body.to_s]
end

def post_json(path, payload)
  http_request(
    method: :post,
    path: path,
    headers: { "Content-Type" => "application/json" },
    body: JSON.generate(payload),
  )
end

def post_form(path, form, basic_auth: nil)
  http_request(
    method: :post,
    path: path,
    headers: { "Content-Type" => "application/x-www-form-urlencoded" },
    body: URI.encode_www_form(form),
    basic_auth: basic_auth,
  )
end

def parse_json!(body, stage)
  JSON.parse(body)
rescue JSON::ParserError => e
  raise CheckFailed.new("[#{stage}] failed to parse JSON: #{e.message}: body=#{body.inspect}")
end

def register_test_user
  suffix = SecureRandom.hex(6)
  payload = {
    "email" => "check-authcore+#{suffix}@example.com",
    "password" => SecureRandom.base64(24),
    "public_id" => "chk#{suffix}",
  }
  status, body = post_json("/v1/auth/register", payload)
  raise CheckFailed.new("register failed: status=#{status} body=#{body}") unless status == 201

  log("register", "ok email=#{payload['email']}")
  payload
end

def login(credentials)
  payload = {
    "identifier" => credentials.fetch("email"),
    "password" => credentials.fetch("password"),
  }
  status, body = post_json("/v1/auth/login", payload)
  raise CheckFailed.new("login failed: status=#{status} body=#{body}") unless status == 200

  parsed = parse_json!(body, "login")
  access_token = parsed["access_token"]
  raise CheckFailed.new("login returned MFA pre_token; this script does not support MFA users") if parsed["pre_token"] && access_token.nil?
  raise CheckFailed.new("login response missing access_token: #{parsed.inspect}") if access_token.to_s.empty?

  log("login", "ok access_token=#{access_token[0, 12]}...")
  access_token
end

def introspect(access_token)
  status, body = post_form(
    "/v1/auth/introspect",
    { "token" => access_token, "token_type_hint" => "access_token" },
    basic_auth: [env!("AUTHCORE_CLIENT_ID"), env!("AUTHCORE_CLIENT_SECRET")],
  )
  raise CheckFailed.new("introspect failed: status=#{status} body=#{body}") unless status == 200

  parsed = parse_json!(body, "introspect")
  raise CheckFailed.new("introspect returned active=false: #{parsed.inspect}") unless parsed["active"] == true

  log("introspect", "ok active=true sub=#{parsed['sub']} aud=#{parsed['aud']} mfa_verified=#{parsed['mfa_verified']}")
  parsed
end

def main
  REQUIRED_ENV.each { |k| env!(k) }
  log("setup", "base_url=#{env!('AUTHCORE_BASE_URL')} client_id=#{env!('AUTHCORE_CLIENT_ID')}")

  credentials = register_test_user
  access_token = login(credentials)
  introspect(access_token)

  log("result", "OK")
  0
rescue CheckFailed => e
  log("result", "NG: #{e.message}")
  1
rescue StandardError => e
  log("result", "NG: #{e.class}: #{e.message}")
  1
end

exit(main) if $PROGRAM_NAME == __FILE__
