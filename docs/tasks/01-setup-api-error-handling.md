# 01: 共通エラーレスポンス / rescue_from 実装

> 依存: なし（Phase 0）

## 概要

`ApplicationController` に共通のエラーハンドラを実装し、
全 API が `{ "error": { "code": "...", "message": "..." } }` 形式で返すようにする。

## 背景・目的

- MVP では JSON シリアライザを導入しないため、エラー形式はコントローラ側で統一する必要がある。
- マイニング層・SNS 層が銀行 API を呼ぶ際、一貫したエラー形式のほうがハンドリングが容易。
- `ActiveRecord::RecordNotFound` / `ActiveRecord::RecordInvalid` / 独自例外を包括的に扱う。

## 影響範囲

- **変更対象**:
  - `app/controllers/application_controller.rb`
  - `app/controllers/concerns/error_responder.rb`（新規）
  - `app/errors/` 配下（新規）に銀行ドメイン固有例外
- **破壊的変更**: なし（現状は何も返していない）
- **外部層（マイニング / SNS）への影響**: エラー形式を公開インターフェースとして固定する

## スキーマ変更

なし

## 実装ステップ

1. `app/errors/bank_error.rb` を新設
   ```ruby
   # 銀行ドメインの基底例外
   class BankError < StandardError
     def initialize(code:, message:, http_status: 422)
       super(message)
       @code = code
       @http_status = http_status
     end

     attr_reader :code, :http_status
   end
   ```
2. `app/errors/insufficient_balance_error.rb` など個別例外を追加
   ```ruby
   class InsufficientBalanceError < BankError
     def initialize(message: "残高が不足しています")
       super(code: "INSUFFICIENT_BALANCE", message: message, http_status: 422)
     end
   end
   ```
3. `app/controllers/concerns/error_responder.rb` を作成
   ```ruby
   module ErrorResponder
     extend ActiveSupport::Concern

     included do
       rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
       rescue_from ActiveRecord::RecordInvalid, with: :render_validation_failed
       rescue_from BankError, with: :render_bank_error
       rescue_from StandardError, with: :render_internal_error unless Rails.env.development?
     end

     private

     def render_error(code:, message:, status:)
       render(
         json: { error: { code: code, message: message, }, },
         status: status,
       )
     end

     def render_not_found(exception)
       render_error(code: "NOT_FOUND", message: exception.message, status: :not_found)
     end

     def render_validation_failed(exception)
       render_error(code: "VALIDATION_FAILED", message: exception.record.errors.full_messages.join(", "), status: :unprocessable_entity)
     end

     def render_bank_error(exception)
       render_error(code: exception.code, message: exception.message, status: exception.http_status)
     end

     def render_internal_error(exception)
       Rails.logger.error(exception.full_message)
       render_error(code: "INTERNAL_ERROR", message: "内部エラーが発生しました", status: :internal_server_error)
     end
   end
   ```
4. `app/controllers/application_controller.rb` で include
   ```ruby
   class ApplicationController < ActionController::API
     include ErrorResponder
   end
   ```

## テスト要件

- `spec/requests/error_handling_spec.rb` を新設
  - 正常系: 普通のレスポンスは変化しない
  - 404: `ActiveRecord::RecordNotFound` 発生時に `{ error: { code: "NOT_FOUND", ... } }` を返す
  - 422: 独自 `BankError` サブクラスを raise した場合、`code` が正しく設定される
  - development 環境では `StandardError` が rescue されないこと（Rails 標準の詳細エラーが出る）
- 検証用のダミーコントローラを `spec/support/` に仕込む（もしくは既存 health_check を拡張）

## 技術的な補足

- `Style/RaiseArgs: compact` に従い、独自例外は `raise BankError.new(code: "...", ...)` ではなく
  `raise BankError, ...` の形で呼ぶ。
- `Style/HashSyntax: never` のため、`code: code,` と明示する。
- HTTP ステータスシンボル（`:unprocessable_entity` 等）で記述して可読性を確保。
- `rescue_from StandardError` は production / staging のみで有効化（dev は Rails の詳細エラーを見たい）。

## 非スコープ

- 認証失敗のエラー（401 / 403）は本タスクでは扱わない（別基盤で扱う）
- 多言語対応（i18n）は MVP 外

## 受け入れ基準

- [ ] `BankError` を raise すると、想定した JSON 形式 + HTTP ステータスで返る
- [ ] `ActiveRecord::RecordNotFound` が 404 + `NOT_FOUND` で返る
- [ ] `ActiveRecord::RecordInvalid` が 422 + `VALIDATION_FAILED` で返る
- [ ] RSpec / RuboCop が通る
