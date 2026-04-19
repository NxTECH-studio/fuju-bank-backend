# request spec の get/post/... に既定で Bearer JWT を差し込む。
# JWT 認証そのものを検証する spec は `skip_default_auth: true` タグで opt-out する。
module AuthenticatedRequest
  %i[get post put patch delete].each do |verb|
    define_method(verb) do |path, **opts|
      meta = RSpec.current_example&.metadata
      unless meta && meta[:skip_default_auth]
        opts[:headers] ||= {}
        has_auth = opts[:headers].any? { |k, _| k.to_s.casecmp("authorization").zero? }
        opts[:headers] = auth_headers.merge(opts[:headers]) unless has_auth
      end
      super(path, **opts)
    end
  end
end
