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

require "json"
require "jwt"
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
    # 同一 external_user_id での再 POST は 200 を返す（B2: lazy provisioning の半分は
    # 「2 回目以降が 500 にならず 200 を返す」点なので、smoke で必ず両経路を踏む）。
    upsert_me(alpha, expected_status: 200)
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
    mint_amount = 1
    client = ActionCableClient.new(uri: @config.bank_cable_uri, access_token: recipient.access_token)
    client.connect(timeout: WS_HANDSHAKE_TIMEOUT_SECONDS)
    client.subscribe(USER_CHANNEL_IDENTIFIER, timeout: WS_HANDSHAKE_TIMEOUT_SECONDS)
    log("ws-#{recipient.label}", "subscribed UserChannel")

    payload = wait_for_credit(client: client, recipient: recipient, mint_amount: mint_amount) do
      mint(actor: actor, recipient: recipient, amount: mint_amount)
    end
    assert_credit_payload!(payload, recipient: recipient, expected_amount: mint_amount)

    log("broadcast", "ok type=#{payload['type']} amount=#{payload['amount']} tx=#{payload['transaction_id']}")
  ensure
    client&.close
  end

  # mint 自体は 200 を返した（mint は raise on non-200）後に WS 配信が来ない場合のため、
  # WSError を CheckFailed に rewrap して「mint は通った / WS 配信レイヤだけ壊れている」と
  # 朝の調査で切り分けやすくする。
  def wait_for_credit(client:, recipient:, mint_amount:, &)
    client.wait_for_message(timeout: WS_BROADCAST_TIMEOUT_SECONDS, &)
  rescue ActionCableClient::WSError => e
    raise CheckFailed.new(
      "#{e.message} (mint HTTP succeeded recipient=#{recipient.label} amount=#{mint_amount}; " \
      "check ActionCable adapter / SolidCable)",
    )
  end

  # broadcast の payload は `Ledger::Notifier#payload_for` が生成する Hash の JSON 化。
  # 期待値は: type=credit / transaction_kind=mint / amount=mint_amount / transaction_id 非空。
  def assert_credit_payload!(payload, recipient:, expected_amount:)
    expected = {
      "type" => "credit",
      "transaction_kind" => "mint",
      "amount" => expected_amount,
    }
    expected.each do |key, value|
      next if payload[key] == value

      raise CheckFailed.new("broadcast #{key} mismatch: got=#{payload[key].inspect} expected=#{value.inspect} (recipient=#{recipient.label})")
    end
    raise CheckFailed.new("broadcast missing transaction_id: #{payload.inspect}") if payload["transaction_id"].to_s.empty?
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

    # body は AuthCore login 失敗時に access_token / pre_token 等を含みうるため、
    # GH Actions ログへの漏出を抑える目的で先頭のみに切り詰める。
    excerpt = body.to_s[0, 200]
    raise CheckFailed.new("#{stage} failed: status=#{status} expected=#{expected} body=#{excerpt}")
  end

  def parse_json!(body, stage)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise CheckFailed.new("[#{stage}] failed to parse JSON: #{e.message}: body=#{body.inspect}")
  end

  # JWT から sub を取り出す（署名検証はサーバー側で済んでいるので payload 部のみ復号）。
  # エラー時に `payload` 全体を出すと PII / 機密クレームが GH Actions ログに乗りうるため、
  # claim 名のリストのみを露出させる。
  def decode_jwt_sub!(token)
    payload, _header = JWT.decode(token, nil, false)
    sub = payload["sub"]
    raise CheckFailed.new("JWT missing sub claim: claims=#{payload.keys.inspect}") if sub.to_s.empty?

    sub
  rescue JWT::DecodeError => e
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

  # websocket-driver の client が要求する `url` / `write` を満たす最小アダプタ。
  # ActionCableClient 本体に直接生やすと WS 利用者向けでない API が漏れるため分離する。
  DriverAdapter = Struct.new(:url, :socket) do
    def write(data) # rubocop:disable Rails/Delegate
      socket.write(data)
    end
  end

  def initialize(uri:, access_token:)
    @uri = uri
    @access_token = access_token
    @messages = []
    @open = false
    @closed = false
    @driver_error = nil
  end

  def connect(timeout:)
    @socket = build_socket
    @driver = WebSocket::Driver.client(
      DriverAdapter.new(@uri.to_s, @socket),
      protocols: [ACTIONCABLE_SUBPROTOCOL, BEARER_SUBPROTOCOL, @access_token],
    )
    register_callbacks
    @driver.start
    pump_until(timeout: timeout) { @open || @closed || @driver_error || disconnected? }
    raise WSError.new("WS handshake failed: #{handshake_failure_summary}") unless @open
  end

  def subscribe(identifier, timeout:)
    send_command("subscribe", identifier)
    pump_until(timeout: timeout) { subscription_confirmed?(identifier) || disconnected? }
    raise WSError.new("WS disconnected during subscribe: reason=#{disconnect_reason}") if disconnected?
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
  rescue StandardError => e
    warn "[ws-close] best-effort cleanup raised #{e.class}: #{e.message}"
  ensure
    @closed = true
  end

  private

  def build_socket
    host = @uri.host
    port = @uri.port || (@uri.scheme == "wss" ? 443 : 80)
    tcp = TCPSocket.new(host, port)
    return tcp unless @uri.scheme == "wss"

    wrap_ssl(tcp, host)
  end

  def wrap_ssl(tcp, host)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.set_params
    ssl = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
    ssl.hostname = host
    ssl.connect
    ssl
  rescue StandardError
    tcp.close
    raise
  end

  def register_callbacks
    @driver.on(:open) { @open = true }
    @driver.on(:close) { @closed = true }
    @driver.on(:error) { |e| @driver_error = e.message }
    @driver.on(:message) { |event| ingest_message(event.data) }
  end

  def ingest_message(data)
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

  # ActionCable は認証拒否や session 切断時に `{"type":"disconnect","reason":"..."}` を送る。
  # 検出するとサブスク待ちのループを早期に抜けて、原因を含めたエラーを raise できる。
  def disconnected?
    @messages.any? { |m| m["type"] == "disconnect" }
  end

  def disconnect_reason
    msg = @messages.find { |m| m["type"] == "disconnect" }
    msg && msg["reason"]
  end

  def handshake_failure_summary
    return "disconnect=#{disconnect_reason}" if disconnected?
    return "driver_error=#{@driver_error}" if @driver_error
    return "closed before open" if @closed

    "timed out before handshake"
  end

  def broadcast_after(baseline)
    @messages[baseline..].to_a.find { |m| m["message"].is_a?(Hash) }&.fetch("message")
  end

  # 条件成立 or タイムアウトまで socket を読みつつ driver にフレームを流し込む。
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
