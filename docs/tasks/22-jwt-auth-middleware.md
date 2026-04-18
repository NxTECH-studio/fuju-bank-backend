# 22: JWT 検証 concern（ローカル検証のみ）

> 依存: #01

## 概要

AuthCore が発行する JWT（RS256）を銀行 API 側でローカル検証する concern を実装する。
MVP では introspection は呼ばず、署名・`exp`・`type=access`・`aud` のみを検証する。

## 背景・目的

- AuthCore 連携の第一歩（メモリ: `project_authcore_integration.md`）。
  金銭移動以外の参照系はローカル JWT 検証で十分軽量にゲートしたい。
- `Authorization: Bearer <jwt>` ヘッダで来るアクセストークンを、
  ApplicationController から見て `current_external_user_id` が取れる状態にする。
- introspection（revocation 検知）は金銭移動系のみで使う想定のため、本タスクでは
  スコープ外に切り出す（#24 で実装、#25 で policy を張る）。

## 影響範囲

- **変更対象**:
  - `app/controllers/concerns/jwt_authenticatable.rb`（新規）
  - `app/controllers/application_controller.rb`（include 追加）
  - `app/errors/authentication_error.rb`（新規。`BankError` サブクラス）
  - `config/initializers/authcore.rb`（新規。公開鍵の読み込み）
  - `spec/support/auth_helpers.rb`（新規。有効な JWT を生成するヘルパー）
  - `spec/requests/authentication_spec.rb`（新規）
  - `Gemfile`（`jwt` gem 追加。未導入なら）
- **破壊的変更**:
  - 既存コントローラに `before_action :authenticate!` が掛かるため、
    認証ヘッダを付けていないクライアントは 401 を受ける。MVP はまだ外部公開されていない前提。
- **外部層への影響**: あり。マイニング層 / SNS 層は今後 AuthCore 発行の JWT を付けて呼ぶ必要がある

## スキーマ変更

なし

## 実装ステップ

1. `jwt` gem を追加（未導入なら）
   ```ruby
   # Gemfile
   gem "jwt"
   ```
2. AuthCore 公開鍵の配置を決める
   - 環境変数 `AUTHCORE_JWT_PUBLIC_KEY`（PEM 文字列）で受け取る方針
   - Docker / Kamal では secret 経由で注入
   - `config/initializers/authcore.rb` で読み込み
     ```ruby
     # frozen_string_literal: true

     # AuthCore 設定。JWT 検証に使う公開鍵と、許容する audience / issuer を集約する。
     module Authcore
       module_function

       def jwt_public_key
         pem = ENV.fetch("AUTHCORE_JWT_PUBLIC_KEY")
         OpenSSL::PKey::RSA.new(pem)
       end

       def expected_audience
         ENV.fetch("AUTHCORE_EXPECTED_AUDIENCE", "authcore")
       end

       def expected_issuer
         ENV.fetch("AUTHCORE_EXPECTED_ISSUER", "authcore")
       end
     end
     ```
3. `app/errors/authentication_error.rb` を追加
   ```ruby
   # 認証失敗を表す例外。ErrorResponder で 401 に変換される。
   class AuthenticationError < BankError
     def initialize(message: "認証に失敗しました")
       super(code: "UNAUTHENTICATED", message: message, http_status: 401)
     end
   end
   ```
4. `app/controllers/concerns/jwt_authenticatable.rb` を新設
   ```ruby
   # Bearer JWT を検証し、current_external_user_id / current_jwt_claims を供給する。
   # ローカル検証のみ（introspection は別 concern で提供）。
   module JwtAuthenticatable
     extend ActiveSupport::Concern

     included do
       before_action :authenticate!
     end

     private

     def authenticate!
       token = extract_bearer_token
       raise AuthenticationError if token.blank?

       @current_jwt_claims = decode_and_verify!(token)
       @current_external_user_id = @current_jwt_claims.fetch("sub")
     end

     def current_jwt_claims
       @current_jwt_claims
     end

     def current_external_user_id
       @current_external_user_id
     end

     def extract_bearer_token
       header = request.headers["Authorization"]
       return nil if header.blank?

       match = header.match(/\ABearer\s+(.+)\z/)
       match && match[1]
     end

     def decode_and_verify!(token)
       payload, _header = JWT.decode(
         token,
         Authcore.jwt_public_key,
         true,
         {
           algorithm: "RS256",
           verify_aud: true,
           aud: Authcore.expected_audience,
           verify_iss: true,
           iss: Authcore.expected_issuer,
           verify_expiration: true,
         },
       )

       raise AuthenticationError, message: "access token 以外は許可されていません" unless payload["type"] == "access"

       payload
     rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidAudError, JWT::InvalidIssuerError
       raise AuthenticationError
     end
   end
   ```
5. `app/controllers/application_controller.rb` で include
   ```ruby
   class ApplicationController < ActionController::API
     include ErrorResponder
     include JwtAuthenticatable
   end
   ```
   - health_check 等で認証を外したいエンドポイントが出たら `skip_before_action :authenticate!` で除外する
6. `spec/support/auth_helpers.rb` を新設
   ```ruby
   module AuthHelpers
     def issue_test_jwt(sub:, type: "access", aud: "authcore", iss: "authcore",
                       exp: 5.minutes.from_now, extra: {})
       payload = {
         sub: sub, type: type, aud: aud, iss: iss,
         exp: exp.to_i, iat: Time.current.to_i,
       }.merge(extra)
       JWT.encode(payload, test_private_key, "RS256")
     end

     def auth_headers(sub: "01HYZ0000000000000000000AA", **opts)
       token = issue_test_jwt(sub: sub, **opts)
       { "Authorization" => "Bearer #{token}", }
     end

     def test_private_key
       # rails_helper で生成済みのキーペアを返す。AUTHCORE_JWT_PUBLIC_KEY には対応する公開鍵を入れる。
       TestKeypair.private_key
     end
   end
   ```
   - `spec/rails_helper.rb` で `ENV["AUTHCORE_JWT_PUBLIC_KEY"]` をテスト用公開鍵に差し替え、
     `RSpec.configure` で `AuthHelpers` を include する
7. `spec/requests/authentication_spec.rb` を新設（下記テスト要件）
8. `make rspec` / `make rubocop` を通す

## テスト要件

ダミーコントローラ（`spec/support/` に仕込む、あるいは既存の health_check 的エンドポイント）を
経由して以下を検証:

- **有効な JWT**: 200 が返り、`current_external_user_id` が取れる
- **ヘッダなし**: 401 + `code: UNAUTHENTICATED`
- **Bearer 以外のスキーム**: 401
- **署名不正（別鍵で署名）**: 401
- **期限切れ（`exp` 過去）**: 401
- **`type` が `refresh`**: 401
- **`aud` 不一致**: 401
- **`iss` 不一致**: 401

## 技術的な補足

- `aud` は MVP では `authcore` を許容。AuthCore 側の audience 設計が固まり次第
  `banking` 等に切り替える（ENV で変更可能）。
- 公開鍵ローテーション（`kid` ヘッダで複数鍵切り替え）は非スコープ。単一鍵固定で実装。
- `introspect` 呼び出しは #24。本タスクでは revocation を検出できない点を明記しておく。
- JWT 検証失敗は全て `AuthenticationError` に畳み、`ErrorResponder#render_bank_error` 経由で
  統一 JSON エラー（`{ error: { code: "UNAUTHENTICATED", message: "..." } }`）を返す。
- `AUTHCORE_JWT_PUBLIC_KEY` は改行を含む PEM 文字列。`.env` では `\n` エスケープ、
  Kamal secret では複数行 string として扱う。

## 非スコープ

- AuthCore `/v1/auth/introspect` の呼び出し → #24
- revocation / MFA gate → #25
- JWK エンドポイントからの公開鍵自動取得 / `kid` ローテーション
- health_check 等の認証除外設計（必要が出たタイミングで `skip_before_action`）

## 受け入れ基準

- [ ] `JwtAuthenticatable` concern が実装され、ApplicationController から include されている
- [ ] 有効な JWT で認証を通過し、`current_external_user_id` が取れる
- [ ] 無効 / 期限切れ / type 不一致 / aud 不一致で 401 + `UNAUTHENTICATED` を返す
- [ ] `AuthenticationError` が `ErrorResponder` 経由で統一エラー JSON に変換される
- [ ] `make rspec` / `make rubocop` が通る
