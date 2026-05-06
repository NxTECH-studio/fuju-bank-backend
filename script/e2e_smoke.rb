#!/usr/bin/env ruby
# frozen_string_literal: true

# fuju-bank E2E 疎通テスト。
#
# AuthCore (register / login) → bank HTTP (/users/me, /ledger/mint) →
# bank ActionCable (UserChannel broadcast) を 1 コマンドで通す。
# CI nightly で常時監視するための smoke 用途であり、ユニットテストの代替ではない。
#
# 各実行で suffix 付きの新規ユーザー 2 名を AuthCore に register する（idempotent
# 用途で固定 user は使わない）。AuthCore / bank に test user が累積するが
# `e2e-smoke-*@example.com` で識別できる。
#
# 使い方:
#   AUTHCORE_BASE_URL=https://auth.fujupay.app/ \
#   BANK_BASE_URL=https://api.fujupay.app/ \
#   BANK_CABLE_URL=wss://api.fujupay.app/cable \
#     bundle exec ruby script/e2e_smoke.rb
#
# 終了コード: 0=success / 1=failure

require "base64"
require "json"
require "net/http"
require "openssl"
require "securerandom"
require "socket"
require "uri"
require "websocket/driver"

# AuthCore + bank 経路を end-to-end で確認するスモークランナー。
class E2ESmoke
  class CheckFailed < StandardError; end

  HTTP_TIMEOUT_SECONDS = 10
  WS_HANDSHAKE_TIMEOUT_SECONDS = 5
  WS_BROADCAST_TIMEOUT_SECONDS = 5
  USER_CHANNEL_IDENTIFIER = JSON.generate({ "channel" => "UserChannel" }).freeze

  # AuthCore / bank の base URL を集約する。env が欠けていれば即 CheckFailed。
  class Config
    attr_reader :authcore_base_uri, :bank_base_uri, :bank_cable_uri

    def self.load
      new(
        authcore_base_url: fetch_env("AUTHCORE_BASE_URL"),
        bank_base_url: fetch_env("BANK_BASE_URL"),
        bank_cable_url: fetch_env("BANK_CABLE_URL"),
      )
    end

    def self.fetch_env(key)
      ENV.fetch(key) { raise CheckFailed.new("missing env var: #{key}") }
    end

    def initialize(authcore_base_url:, bank_base_url:, bank_cable_url:)
      @authcore_base_uri = URI.parse(authcore_base_url)
      @bank_base_uri = URI.parse(bank_base_url)
      @bank_cable_uri = URI.parse(bank_cable_url)
    end
  end

  # smoke 実行 1 回分の test user。
  class TestUser
    attr_reader :role, :email, :password, :public_id
    attr_accessor :access_token, :external_user_id

    def initialize(role:)
      suffix = SecureRandom.hex(6)
      @role = role
      @email = "e2e-smoke-#{role}+#{suffix}@example.com"
      @password = SecureRandom.base64(24)
      @public_id = "smk#{role[0]}#{suffix}"
    end

    def label
      "#{role}/#{public_id}"
    end
  end

  def initialize(config:)
    @config = config
  end

  def run
    log("setup", "authcore=#{@config.authcore_base_uri} bank=#{@config.bank_base_uri} cable=#{@config.bank_cable_uri}")

    alpha = register_and_login(role: "alpha")
    beta = register_and_login(role: "beta")

    upsert_me(alpha, expected_status: 201)
    upsert_me(beta, expected_status: 201)
    show_me(alpha)

    receive_broadcast_during_mint(actor: alpha, recipient: beta)

    logout(alpha)
    logout(beta)

    log("result", "OK")
  end

  private

  def register_and_login(role:)
    user = TestUser.new(role: role)
    register(user)
    login(user)
    user
  end

  def register(user)
    payload = {
      "email" => user.email,
      "password" => user.password,
      "public_id" => user.public_id,
    }
    status, body = authcore_post_json("/v1/auth/register", payload)
    expect_status!("register-#{user.label}", status, body, expected: 201)
    log("register-#{user.label}", "ok email=#{user.email}")
  end

  def login(user)
    status, body = authcore_post_json(
      "/v1/auth/login",
      { "identifier" => user.email, "password" => user.password },
    )
    expect_status!("login-#{user.label}", status, body, expected: 200)

    parsed = parse_json!(body, "login")
    raise CheckFailed.new("login returned MFA pre_token; this script does not support MFA users") if parsed["pre_token"]

    access_token = parsed["access_token"]
    raise CheckFailed.new("login response missing access_token: #{parsed.inspect}") if access_token.to_s.empty?

    user.access_token = access_token
    user.external_user_id = decode_jwt_sub!(access_token)
    log("login-#{user.label}", "ok sub=#{user.external_user_id}")
  end

  def upsert_me(user, expected_status:)
    payload = {
      "name" => user.public_id,
      "public_key" => SecureRandom.alphanumeric(64),
    }
    status, body = bank_request(
      method: :post,
      path: "/users/me",
      access_token: user.access_token,
      json: payload,
    )
    expect_status!("upsert_me-#{user.label}", status, body, expected: expected_status)
    log("upsert_me-#{user.label}", "ok status=#{status}")
  end

  def show_me(user)
    status, body = bank_request(method: :get, path: "/users/me", access_token: user.access_token)
    expect_status!("show_me-#{user.label}", status, body, expected: 200)

    parsed = parse_json!(body, "show_me")
    raise CheckFailed.new("show_me missing balance_fuju: #{parsed.inspect}") unless parsed.has_key?("balance_fuju")

    log("show_me-#{user.label}", "ok balance=#{parsed['balance_fuju']}")
  end

  # recipient の WS で UserChannel を購読した状態で actor から mint を発火し、
  # 5 秒以内に credit broadcast が届くことを確認する。WS は ensure で必ず閉じる。
  def receive_broadcast_during_mint(actor:, recipient:)
    client = ActionCableClient.new(uri: @config.bank_cable_uri, access_token: recipient.access_token)
    client.connect(timeout: WS_HANDSHAKE_TIMEOUT_SECONDS)
    client.subscribe(USER_CHANNEL_IDENTIFIER, timeout: WS_HANDSHAKE_TIMEOUT_SECONDS)
    log("ws-#{recipient.label}", "subscribed UserChannel")

    payload = client.wait_for_message(timeout: WS_BROADCAST_TIMEOUT_SECONDS) do
      mint(actor: actor, recipient: recipient, amount: 1)
    end
    raise CheckFailed.new("broadcast missing transaction_id: #{payload.inspect}") if payload["transaction_id"].nil?

    log("broadcast", "ok type=#{payload['type']} amount=#{payload['amount']} tx=#{payload['transaction_id']}")
  ensure
    client&.close
  end

  def mint(actor:, recipient:, amount:)
    payload = {
      "ledger" => {
        "user_id" => recipient.external_user_id,
        "amount" => amount,
        "metadata" => { "source" => "e2e-smoke" },
      },
    }
    status, body = bank_request(
      method: :post,
      path: "/ledger/mint",
      access_token: actor.access_token,
      json: payload,
      headers: { "Idempotency-Key" => "e2e-smoke-mint-#{SecureRandom.uuid}" },
    )
    expect_status!("mint", status, body, expected: 200)
    log("mint", "ok amount=#{amount} -> #{recipient.label}")
  end

  # AuthCore に logout エンドポイントが無い / token 即時失効する実装の場合に
  # smoke 全体を落とさないため best-effort で叩く。
  def logout(user)
    status, _body = authcore_post_json("/v1/auth/logout", {}, access_token: user.access_token)
    log("logout-#{user.label}", "status=#{status}")
  rescue StandardError => e
    log("logout-#{user.label}", "skipped (#{e.class}: #{e.message})")
  end

  # ---- HTTP helpers ----

  def authcore_post_json(path, payload, access_token: nil)
    http_request(
      base_uri: @config.authcore_base_uri,
      method: :post,
      path: path,
      headers: { "Content-Type" => "application/json" }.merge(bearer_header(access_token)),
      body: JSON.generate(payload),
    )
  end

  def bank_request(method:, path:, access_token:, json: nil, headers: {})
    request_headers = headers.merge(bearer_header(access_token))
    request_headers["Content-Type"] = "application/json" if json

    http_request(
      base_uri: @config.bank_base_uri,
      method: method,
      path: path,
      headers: request_headers,
      body: json && JSON.generate(json),
    )
  end

  def bearer_header(access_token)
    return {} if access_token.nil?

    { "Authorization" => "Bearer #{access_token}" }
  end

  def http_request(base_uri:, method:, path:, headers:, body: nil)
    uri = URI.join(base_uri, path)
    req = build_http_request(method, uri)
    headers.each { |k, v| req[k] = v }
    req.body = body if body

    response = Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: HTTP_TIMEOUT_SECONDS,
      read_timeout: HTTP_TIMEOUT_SECONDS,
    ) { |http| http.request(req) }

    [response.code.to_i, response.body]
  end

  def build_http_request(method, uri)
    case method
    when :post
      Net::HTTP::Post.new(uri)
    when :get
      Net::HTTP::Get.new(uri)
    else
      raise CheckFailed.new("unsupported HTTP method: #{method}")
    end
  end

  # ---- Validation helpers ----

  def expect_status!(stage, status, body, expected:)
    return if status == expected

    raise CheckFailed.new("#{stage} failed: status=#{status} expected=#{expected} body=#{body}")
  end

  def parse_json!(body, stage)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise CheckFailed.new("[#{stage}] failed to parse JSON: #{e.message}: body=#{body.inspect}")
  end

  # JWT から sub を取り出す（署名検証はサーバー側で済んでいるので payload 部のみ復号）。
  def decode_jwt_sub!(token)
    payload_b64 = token.split(".")[1]
    raise CheckFailed.new("invalid JWT (no payload segment)") if payload_b64.nil?

    padded = payload_b64 + ("=" * ((4 - (payload_b64.size % 4)) % 4))
    parsed = JSON.parse(Base64.urlsafe_decode64(padded))
    sub = parsed["sub"]
    raise CheckFailed.new("JWT missing sub claim: #{parsed.inspect}") if sub.to_s.empty?

    sub
  rescue JSON::ParserError, ArgumentError => e
    raise CheckFailed.new("failed to decode JWT: #{e.class}: #{e.message}")
  end

  def log(stage, message)
    warn "[#{stage}] #{message}"
  end
end

# ActionCable の subprotocol JWT を最小限ラップする WebSocket クライアント。
# bank の ApplicationCable::Connection は
# `Sec-WebSocket-Protocol: actioncable-v1-json, bearer, <jwt>` を期待するため、
# websocket-driver の protocols 引数にその 3 値を渡す。
class ActionCableClient # rubocop:disable Style/OneClassPerFile
  class WSError < StandardError; end

  ACTIONCABLE_SUBPROTOCOL = "actioncable-v1-json"
  BEARER_SUBPROTOCOL = "bearer"
  READ_CHUNK_BYTES = 4096

  def initialize(uri:, access_token:)
    @uri = uri
    @access_token = access_token
    @messages = []
    @open = false
    @closed = false
    @driver_error = nil
  end

  # websocket-driver は内部で `url` と `write` を呼ぶため、self を渡す。
  def url
    @uri.to_s
  end

  def write(data) # rubocop:disable Rails/Delegate
    @socket.write(data)
  end

  def connect(timeout:)
    @socket = build_socket
    @driver = WebSocket::Driver.client(
      self,
      protocols: [ACTIONCABLE_SUBPROTOCOL, BEARER_SUBPROTOCOL, @access_token],
    )
    register_callbacks
    @driver.start
    pump_until(timeout: timeout) { @open || @closed || @driver_error }
    raise WSError.new("WS handshake failed: #{@driver_error || 'closed before open'}") unless @open
  end

  def subscribe(identifier, timeout:)
    send_command("subscribe", identifier)
    pump_until(timeout: timeout) { subscription_confirmed?(identifier) }
    raise WSError.new("subscription not confirmed within #{timeout}s") unless subscription_confirmed?(identifier)
  end

  # block を実行してから timeout 秒以内に到着した最初の broadcast (`message` field を持つ)
  # ペイロードを返す。ping / welcome 等の制御フレームは無視する。
  def wait_for_message(timeout:)
    baseline = @messages.size
    yield if block_given?
    pump_until(timeout: timeout) { broadcast_after(baseline) }
    payload = broadcast_after(baseline)
    raise WSError.new("did not receive broadcast within #{timeout}s") unless payload

    payload
  end

  def close
    return if @closed

    @driver&.close
    @socket&.close
  rescue StandardError
    # best-effort cleanup
  ensure
    @closed = true
  end

  private

  def build_socket
    host = @uri.host
    port = @uri.port || (@uri.scheme == "wss" ? 443 : 80)
    tcp = TCPSocket.new(host, port)
    return tcp unless @uri.scheme == "wss"

    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.set_params
    ssl = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
    ssl.hostname = host
    ssl.connect
    ssl
  end

  def register_callbacks
    @driver.on(:open) { @open = true }
    @driver.on(:close) { @closed = true }
    @driver.on(:error) { |e| @driver_error = e.message }
    @driver.on(:message) { |event| ingest_frame(event.data) }
  end

  def ingest_frame(data)
    return if data.to_s.empty?

    @messages << JSON.parse(data)
  rescue JSON::ParserError
    # ignore non-JSON control frames
  end

  def send_command(command, identifier)
    @driver.text(JSON.generate({ "command" => command, "identifier" => identifier }))
  end

  def subscription_confirmed?(identifier)
    @messages.any? { |m| m["type"] == "confirm_subscription" && m["identifier"] == identifier }
  end

  def broadcast_after(baseline)
    @messages[baseline..].to_a.find { |m| m["message"].is_a?(Hash) }&.fetch("message")
  end

  # 条件成立 or タイムアウトまで socket を読みつつ driver にフレームを流し込む。
  # 戻り値の意味は呼び元で重要にしないよう、条件成立は呼び元で再評価して判定する。
  def pump_until(timeout:)
    deadline = monotonic_now + timeout
    until yield
      remaining = deadline - monotonic_now
      break if remaining <= 0

      ready = @socket.wait_readable(remaining)
      break if ready.nil?

      chunk = read_chunk
      break if chunk.nil?
      next if chunk.empty?

      @driver.parse(chunk)
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def read_chunk
    @socket.read_nonblock(READ_CHUNK_BYTES)
  rescue IO::WaitReadable
    ""
  rescue EOFError
    nil
  end
end

# rubocop:disable Rails/Exit
begin
  E2ESmoke.new(config: E2ESmoke::Config.load).run
  exit 0
rescue E2ESmoke::CheckFailed, ActionCableClient::WSError => e
  warn "[result] NG: #{e.message}"
  exit 1
rescue StandardError => e
  warn "[result] NG: #{e.class}: #{e.message}"
  warn e.backtrace.first(10).join("\n")
  exit 1
end
# rubocop:enable Rails/Exit
