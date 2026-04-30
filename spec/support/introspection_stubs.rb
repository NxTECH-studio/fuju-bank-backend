module IntrospectionStubs
  INTROSPECT_ENDPOINT = "https://auth.fuju.example/v1/auth/introspect".freeze

  def stub_active_introspection(sub: "01HYZ0000000000000000000AA", mfa_verified: false, scope: "", **overrides)
    payload = {
      "active" => true,
      "sub" => sub,
      "client_id" => "bank-client",
      "token_type" => "access_token",
      "mfa_verified" => mfa_verified,
      "scope" => scope,
      "aud" => "authcore",
      "exp" => 5.minutes.from_now.to_i,
      "iat" => Time.current.to_i,
    }.merge(overrides)

    stub_request(:post, INTROSPECT_ENDPOINT).to_return(
      status: 200,
      body: payload.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  # AuthCore の service token introspect レスポンスを模す。username は返らず
  # mfa_verified は常に false（実装側 introspect_uc も同様）。sub には
  # 呼び出し元クライアントの client_id（例: fuju-emotion-model）が入る。
  def stub_active_service_introspection(client_id: "fuju-emotion-model", scope: "", **overrides)
    stub_active_introspection(
      sub: client_id, mfa_verified: false, scope: scope,
      "username" => nil, **overrides,
    )
  end

  def stub_inactive_introspection
    stub_request(:post, INTROSPECT_ENDPOINT).to_return(
      status: 200,
      body: { "active" => false }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  def stub_introspection_server_error
    stub_request(:post, INTROSPECT_ENDPOINT).to_return(status: 500, body: "")
  end
end
