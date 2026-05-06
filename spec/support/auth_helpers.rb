module AuthHelpers
  def issue_test_jwt(sub:, type: "access", aud: "authcore", iss: "authcore",
                     exp: 5.minutes.from_now, key: test_private_key, extra: {})
    payload = {
      sub: sub, type: type, aud: aud, iss: iss,
      exp: exp.to_i, iat: Time.current.to_i,
    }.merge(extra)
    JWT.encode(payload, key, "RS256")
  end

  def auth_headers(sub: "01HYZ0000000000000000000AA", **)
    token = issue_test_jwt(sub: sub, **)
    { "Authorization" => "Bearer #{token}" }
  end

  # Service-to-Service 経路用の Bearer ヘッダ。`sub` は呼び出し元クライアント
  # の client_id（例: fuju-emotion-model）。AuthCore が発行する service token
  # と同じ shape を持たせる。
  def service_auth_headers(client_id: "fuju-emotion-model", scope: "", **)
    token = issue_test_jwt(sub: client_id, type: "service", extra: { scope: scope }, **)
    { "Authorization" => "Bearer #{token}" }
  end

  def test_private_key
    TestKeypair.private_key
  end
end
