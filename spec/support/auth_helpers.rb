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

  def test_private_key
    TestKeypair.private_key
  end
end
