# 24: AuthCore introspection クライアント

> 依存: #22
> 前提ブロック: AuthCore から `client_id` / `client_secret` の受領後に着手

## 概要

AuthCore の `POST /v1/auth/introspect` を叩くクライアントを実装する。
revocation 検出・MFA 検証など、ローカル JWT 検証だけでは判断できない属性を取得するための土台。
本タスクでは「呼び出して結果を構造体で返す」ところまで。コントローラへの適用は #25。

## 背景・目的

- ローカル JWT 検証（#22）では revocation を検知できない。金銭移動系では
  必ず introspection で `active=true` を確認する方針（メモリ: `project_authcore_integration.md`）。
- `mfa_verified` 等の将来属性も introspection で供給される。
- AuthCore との HTTP 連携を 1 箇所にまとめ、retry / エラー変換方針を固定する。

## 影響範囲

- **変更対象**:
  - `app/services/authcore/introspection_client.rb`（新規）
  - `app/services/authcore/introspection_result.rb`（新規。構造体）
  - `app/errors/authcore_unavailable_error.rb`（新規。503 相当）
  - `app/errors/token_inactive_error.rb`（新規。401 相当）
  - `config/initializers/authcore.rb`（#22 で作成済み。`base_url` / `client_id` / `client_secret` を追加）
  - `spec/services/authcore/introspection_client_spec.rb`（新規）
  - `Gemfile`（`faraday` 未導入なら追加。標準 `Net::HTTP` で済ますなら不要）
- **破壊的変更**: なし
- **外部層への影響**: なし（本タスクでは内部サービスを追加するだけ）

## スキーマ変更

なし

## 実装ステップ

1. 環境変数を定義
   - `AUTHCORE_BASE_URL`（例: `https://auth.fuju.example`）
   - `AUTHCORE_CLIENT_ID`
   - `AUTHCORE_CLIENT_SECRET`
2. `config/initializers/authcore.rb` に accessor を追加
   ```ruby
   module Authcore
     module_function

     def base_url
       ENV.fetch("AUTHCORE_BASE_URL")
     end

     def client_id
       ENV.fetch("AUTHCORE_CLIENT_ID")
     end

     def client_secret
       ENV.fetch("AUTHCORE_CLIENT_SECRET")
     end
     # jwt_public_key / expected_audience / expected_issuer は #22 で定義済み
   end
   ```
3. `app/errors/authcore_unavailable_error.rb`
   ```ruby
   # AuthCore への問い合わせが失敗した際の例外。ErrorResponder で 503 に変換。
   class AuthcoreUnavailableError < BankError
     def initialize(message: "認証基盤に接続できません")
       super(code: "AUTHCORE_UNAVAILABLE", message: message, http_status: 503)
     end
   end
   ```
4. `app/errors/token_inactive_error.rb`
   ```ruby
   # introspection で active=false が返った場合の例外。401 に変換。
   class TokenInactiveError < BankError
     def initialize(message: "トークンが無効化されています")
       super(code: "TOKEN_INACTIVE", message: message, http_status: 401)
     end
   end
   ```
5. `app/services/authcore/introspection_result.rb`
   ```ruby
   # AuthCore の introspect レスポンスを扱う値オブジェクト。
   class Authcore::IntrospectionResult
     attr_reader :active, :sub, :client_id, :username, :token_type,
                 :mfa_verified, :aud, :exp, :iat

     def initialize(payload)
       @active        = payload["active"]
       @sub           = payload["sub"]
       @client_id     = payload["client_id"]
       @username      = payload["username"]
       @token_type    = payload["token_type"]
       @mfa_verified  = payload["mfa_verified"]  # 将来対応で入る予定
       @aud           = payload["aud"]
       @exp           = payload["exp"]
       @iat           = payload["iat"]
     end

     def active?
       @active == true
     end

     def mfa_verified?
       @mfa_verified == true
     end
   end
   ```
6. `app/services/authcore/introspection_client.rb`
   ```ruby
   # AuthCore の /v1/auth/introspect を呼び出すクライアント。
   # 成功時: IntrospectionResult を返す
   # active=false: TokenInactiveError を raise（フェイルクローズ）
   # HTTP / ネットワーク失敗: AuthcoreUnavailableError を raise
   class Authcore::IntrospectionClient
     ENDPOINT_PATH = "/v1/auth/introspect".freeze
     TIMEOUT_SECONDS = 3

     def self.call(token:)
       new(token: token).call
     end

     def initialize(token:)
       @token = token
     end

     def call
       response = post_introspect
       raise AuthcoreUnavailableError if response.code.to_i >= 500

       payload = JSON.parse(response.body)
       result = Authcore::IntrospectionResult.new(payload)
       raise TokenInactiveError unless result.active?

       result
     rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
       raise AuthcoreUnavailableError
     rescue JSON::ParserError
       raise AuthcoreUnavailableError, message: "AuthCore のレスポンスを解釈できません"
     end

     private

     def post_introspect
       uri = URI.join(Authcore.base_url, ENDPOINT_PATH)
       req = Net::HTTP::Post.new(uri)
       req.basic_auth(Authcore.client_id, Authcore.client_secret)
       req["Content-Type"] = "application/x-www-form-urlencoded"
       req.body = URI.encode_www_form(token: @token, token_type_hint: "access_token")

       Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                               open_timeout: TIMEOUT_SECONDS,
                                               read_timeout: TIMEOUT_SECONDS) do |http|
         http.request(req)
       end
     end
   end
   ```
7. `spec/services/authcore/introspection_client_spec.rb` を WebMock で書く
8. `make rspec` / `make rubocop` を通す

## テスト要件

WebMock で AuthCore 側のレスポンスをスタブ:

- **200 + active=true**: `IntrospectionResult` が返り、`sub` / `client_id` / `username` /
  `mfa_verified` 等が取れる
- **200 + active=false**: `TokenInactiveError` が raise される（401 相当）
- **401 レスポンス（client 認証失敗）**: `AuthcoreUnavailableError` が raise される
  （アプリのバグ扱い。401 透過ではなく 503 側に寄せる）
- **500 レスポンス**: `AuthcoreUnavailableError`
- **タイムアウト**: `AuthcoreUnavailableError`
- **接続失敗**: `AuthcoreUnavailableError`
- **JSON 不正**: `AuthcoreUnavailableError`

リクエストの妥当性:

- `Authorization: Basic <base64(client_id:client_secret)>` が付与されていること
- `Content-Type: application/x-www-form-urlencoded`
- body が `token=<jwt>&token_type_hint=access_token`

## 技術的な補足

- HTTP クライアントは `Net::HTTP`（標準ライブラリ）で統一。`faraday` を使いたい場合は
  別途検討するが、依存を増やさない方針で一旦標準。
- フェイルクローズ方針: AuthCore 側のエラーが判別できない場合は必ず 503 を返し、
  誤って通過させない（金銭移動系に適用される想定のため）。
- `TokenInactiveError` と `AuthenticationError`（#22）は別例外として分離。
  前者は「トークン自体は正しいが revoke 済み」、後者は「署名不正 / 期限切れ / 形式不正」。
  運用時のログで区別できるようにする。
- retry はしない（AuthCore が落ちていれば素直に 503 を返す）。
- レスポンスのキャッシュもしない（revocation 検出の即応性が目的）。
- `mfa_verified` は AuthCore 側の将来対応属性。`nil` の場合は `false` 相当に扱う（`mfa_verified?` 参照）。

## 非スコープ

- introspection 結果のキャッシュ（短 TTL のメモリキャッシュ等）
- コントローラ層への適用（before_action で呼ぶ） → #25
- MFA 要求ポリシーの定義 → #25
- retry / サーキットブレーカー

## 受け入れ基準

- [ ] `Authcore::IntrospectionClient.call(token: ...)` が `IntrospectionResult` を返す
- [ ] `active=false` / HTTP 5xx / タイムアウト / JSON 不正を所定の例外に変換する
- [ ] HTTP Basic 認証・form-urlencoded body のリクエスト仕様を満たす
- [ ] WebMock ベースのテストが網羅されている
- [ ] `make rspec` / `make rubocop` が通る
