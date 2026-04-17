# 13: POST /artists エンドポイント

> 依存: #01, #09

## 概要

Artist を作成する API。作成時に `Account(kind: "artist")` が自動生成される（#09 の after_create）。

## 背景・目的

- Artist 登録が全てのシナリオの起点。
- 初期は管理者が手動で叩くことを想定（認証は別基盤、MVP では未認証）。

## 影響範囲

- **変更対象**:
  - `config/routes.rb`
  - `app/controllers/artists_controller.rb`（新規）
  - `spec/requests/artists_spec.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: 新規エンドポイント公開

## スキーマ変更

なし

## 実装ステップ

1. routes
   ```ruby
   # config/routes.rb
   Rails.application.routes.draw do
     get "up" => "rails/health#show", as: :rails_health_check

     resources :artists, only: [:create, :show] do
       resources :transactions, only: [:index], controller: "artist_transactions"
     end
     # ...（他のルートは後続タスクで追加）
   end
   ```
2. コントローラ
   ```ruby
   # app/controllers/artists_controller.rb
   # TODO: 認証は将来拡張（別基盤）
   class ArtistsController < ApplicationController
     def create
       artist = Artist.create!(artist_params)
       render(json: serialize(artist), status: :created)
     end

     private

     def artist_params
       params.expect(artist: [:name, :public_key])
     end

     def serialize(artist)
       {
         id: artist.id,
         name: artist.name,
         public_key: artist.public_key,
         balance_fuju: artist.account.balance_fuju,
         created_at: artist.created_at.iso8601,
       }
     end
   end
   ```
3. Request spec
   ```ruby
   # spec/requests/artists_spec.rb
   require "rails_helper"

   RSpec.describe "POST /artists", type: :request do
     it "creates artist with account" do
       expect { post "/artists", params: { artist: { name: "Alice" } } }
         .to change(Artist, :count).by(1)
         .and change(Account, :count).by(1)
       expect(response).to have_http_status(:created)
       expect(response.parsed_body).to include("name" => "Alice", "balance_fuju" => 0)
     end

     it "returns VALIDATION_FAILED when name is missing" do
       post "/artists", params: { artist: { name: "" } }
       expect(response).to have_http_status(:unprocessable_entity)
       expect(response.parsed_body.dig("error", "code")).to eq("VALIDATION_FAILED")
     end
   end
   ```

## テスト要件

- 正常系: 201 + Artist + Account 作成
- 異常系: name 空で 422（`VALIDATION_FAILED`）
- レスポンスに `balance_fuju` が含まれる
- `bullet` 警告無し（`artist.account.balance_fuju` 参照時に N+1 になっていないか確認。MVP は 1 件作成直後なので問題なし）

## 技術的な補足

- Rails 8 では `params.expect` が標準化（Strong Parameters の新記法）。
- レスポンスはプレーン Hash。シリアライザは導入しない（#00-overview の方針）。
- `public_key` は MVP では nil でも OK（カラム自体 nullable）。
- `ApplicationController#rescue_from ActiveRecord::RecordInvalid`（#01）が 422 レスポンスを生成する。

## 非スコープ

- 認証（別基盤）
- 一覧 API（`GET /artists`）は MVP 外
- 更新・削除 API は MVP 外

## 受け入れ基準

- [ ] `POST /artists` で 201 が返る
- [ ] レスポンスに `balance_fuju: 0` が含まれる
- [ ] 異常系で `{ error: { code: "VALIDATION_FAILED", ... } }` が返る
- [ ] RSpec / RuboCop が通る
