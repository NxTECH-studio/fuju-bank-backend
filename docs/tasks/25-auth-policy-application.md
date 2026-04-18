# 25: 認証ポリシー適用（参照系 = ローカル / 金銭移動系 = introspection）

> 依存: #22, #24
> 推奨: #23（`current_user` が使える状態）

## 概要

既存エンドポイントに対して認証ポリシーを差し込む。参照系はローカル JWT 検証のみ（#22 で既に適用済み）、
金銭移動系（`/mint`, `/transfer` 等）は追加で introspection を呼んでフェイルクローズする。
MFA 要求の差し込みポイントも用意する（実際に `mfa_verified=true` を要求する操作は後続で決める）。

## 背景・目的

- 全エンドポイントが同じコスト（introspection 必須）で動くと AuthCore への負荷が読めない。
- revocation を金銭移動の前に必ず検知する必要がある（二重発行・不正送金の防止）。
- MFA gate の骨組みだけ用意し、将来「高額 transfer には MFA 必須」等を追加しやすくする。

## 影響範囲

- **変更対象**:
  - `app/controllers/concerns/introspection_required.rb`（新規。金銭移動系でのみ include）
  - `app/controllers/concerns/mfa_required.rb`（新規。特定 action で include）
  - `app/errors/mfa_required_error.rb`（新規。403 相当）
  - 対象コントローラ（#16 / #17 の実装状況に応じて）:
    - `app/controllers/ledger/mint_controller.rb` 相当
    - `app/controllers/ledger/transfer_controller.rb` 相当
  - `spec/requests/ledger/mint_spec.rb` / `spec/requests/ledger/transfer_spec.rb`
    にポリシー適用ケースを追加
- **破壊的変更**:
  - 金銭移動系エンドポイントは有効 JWT + `active=true` が必須になる
  - 本番で revoke されたトークンは 401 を受ける
- **外部層への影響**: マイニング層からの mint / SNS 層からの transfer は
  AuthCore で認証されたトークンで叩く必要がある（合意済み方針）

## スキーマ変更

なし

## 実装ステップ

1. `app/errors/mfa_required_error.rb`
   ```ruby
   # MFA 未検証のトークンで MFA 必須エンドポイントを叩いたときの例外。
   class MfaRequiredError < BankError
     def initialize(message: "この操作には MFA 検証が必要です")
       super(code: "MFA_REQUIRED", message: message, http_status: 403)
     end
   end
   ```
2. `app/controllers/concerns/introspection_required.rb`
   ```ruby
   # ローカル JWT 検証（JwtAuthenticatable）の後段で AuthCore introspection を呼ぶ。
   # 金銭移動系コントローラでのみ include する。
   module IntrospectionRequired
     extend ActiveSupport::Concern

     included do
       before_action :verify_introspection!
     end

     private

     def verify_introspection!
       token = extract_bearer_token  # JwtAuthenticatable で定義済み
       @introspection_result = Authcore::IntrospectionClient.call(token: token)

       # ローカル検証の sub と introspection の sub が一致すること（念のため）
       raise AuthenticationError if @introspection_result.sub != current_external_user_id
     end

     def introspection_result
       @introspection_result
     end
   end
   ```
3. `app/controllers/concerns/mfa_required.rb`
   ```ruby
   # MFA 検証済みトークンのみ許可する。IntrospectionRequired の後に include すること。
   module MfaRequired
     extend ActiveSupport::Concern

     included do
       before_action :require_mfa_verified!
     end

     private

     def require_mfa_verified!
       raise MfaRequiredError unless introspection_result&.mfa_verified?
     end
   end
   ```
4. 金銭移動系コントローラに include
   ```ruby
   # app/controllers/ledger/mint_controller.rb
   class Ledger::MintController < ApplicationController
     include IntrospectionRequired
     # MFA 要否は MVP 時点では未決定。必要になった時点で `include MfaRequired` を追加する。
   end

   # app/controllers/ledger/transfer_controller.rb
   class Ledger::TransferController < ApplicationController
     include IntrospectionRequired
   end
   ```
   - #16 / #17 の実装状況を確認し、実ファイル名に合わせる
5. 参照系（#14 残高参照 / #18 取引履歴 等）は `JwtAuthenticatable` のみ。
   変更は不要（ApplicationController から継承するだけ）。
6. `spec/requests/ledger/mint_spec.rb` / `spec/requests/ledger/transfer_spec.rb` に
   ポリシー適用ケースを追加（WebMock で introspection をスタブ）
7. `make rspec` / `make rubocop` を通す

## ポリシー表

| エンドポイント | ローカル JWT 検証 | introspection | MFA 要求 |
|---|---|---|---|
| `GET /users/:id/balance`（#14） | 必須 | 不要 | 不要 |
| `GET /ledger/transactions`（#18） | 必須 | 不要 | 不要 |
| `GET /artifacts`（#15） | 必須 | 不要 | 不要 |
| `POST /ledger/mint`（#16） | 必須 | **必須** | 将来検討 |
| `POST /ledger/transfer`（#17） | 必須 | **必須** | 将来検討 |
| `ActionCable /cable`（#19） | 必須（別途 Channel 認証） | 不要 | 不要 |

MFA 要求対象の洗い出しは本タスクの非スコープ。骨組みだけ用意する。

## テスト要件

- **mint エンドポイント**
  - 有効 JWT + introspection active=true → 成功
  - 有効 JWT + introspection active=false → 401 + `TOKEN_INACTIVE`
  - 有効 JWT + introspection が 5xx → 503 + `AUTHCORE_UNAVAILABLE`
  - 有効 JWT + introspection `sub` とローカル `sub` が食い違う → 401 + `UNAUTHENTICATED`
  - 無効 JWT → 401 + `UNAUTHENTICATED`（`JwtAuthenticatable` で先に弾かれる）
- **transfer エンドポイント**: mint と同等
- **参照系（balance 等）**
  - 有効 JWT で 200（introspection は呼ばれないことを確認。WebMock で期待コール数 0）
- **MFA gate（ダミー test controller で検証）**
  - `mfa_verified=true` → 通過
  - `mfa_verified=false` / nil → 403 + `MFA_REQUIRED`

## 技術的な補足

- `include` の順序: `IntrospectionRequired` → `MfaRequired` の順で include すること
  （MFA check は introspection 結果に依存するため）。
- `ApplicationController` 全体に `IntrospectionRequired` を入れない理由:
  - AuthCore への問い合わせコスト
  - 参照系で revocation 判定が即時である必要は薄い
  - 金銭移動系と参照系の責務を明確に分離しておくほうが後でポリシーを動かしやすい
- `sub` 一致チェックは念押し（通常はローカル検証と一致するが、JWT と別人の introspection が
  返ってくる異常系を確実に塞ぐ）。
- introspection 結果のキャッシュは引き続き非スコープ。高負荷が見えてきたら検討。
- 将来の MFA 要求候補:
  - 一定額以上の transfer
  - 自分以外の Account への initial transfer
  - ユーザー設定の変更系（#23 で作らない PATCH 系）
- `ActionCable` の認証は本タスクでは触らない（#19 で別途設計）。

## 非スコープ

- introspection 結果のキャッシュ
- MFA 要求対象エンドポイントの確定（どれに `MfaRequired` を掛けるか）
- ActionCable の認証適用
- レート制限 / 監査ログ

## 受け入れ基準

- [ ] `IntrospectionRequired` concern が金銭移動系コントローラに適用されている
- [ ] `MfaRequired` concern が用意されており、単体テストで 403 を返すことを確認
- [ ] revoke されたトークンで mint / transfer が 401 を受ける
- [ ] AuthCore 不通時に mint / transfer が 503 を受ける（フェイルクローズ）
- [ ] 参照系では introspection が呼ばれない
- [ ] `make rspec` / `make rubocop` が通る
