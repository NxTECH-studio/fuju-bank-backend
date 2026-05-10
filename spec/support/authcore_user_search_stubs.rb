module AuthcoreUserSearchStubs
  USER_SEARCH_ENDPOINT = "https://auth.fuju.example/v1/users/search".freeze

  def stub_authcore_user_search(users:, query: nil, limit: nil)
    filter = {}
    filter[:q] = query if query.present?
    filter[:limit] = limit.to_s if limit.present?

    stub_request(:get, USER_SEARCH_ENDPOINT).with(query: hash_including(filter)).to_return(
      status: 200,
      body: { "users" => users }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  def stub_authcore_user_search_error(status: 500)
    stub_request(:get, USER_SEARCH_ENDPOINT).with(query: hash_including({})).to_return(status: status, body: "")
  end

  def stub_authcore_user_search_timeout
    stub_request(:get, USER_SEARCH_ENDPOINT).with(query: hash_including({})).to_timeout
  end
end
