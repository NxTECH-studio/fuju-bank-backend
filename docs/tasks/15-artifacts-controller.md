# 15: Artifacts コントローラ（POST /artifacts, GET /artifacts/:id）

> 依存: #01, #10

## 概要

Artifact 登録・参照 API を実装する。

## 背景・目的

- マイニング層 / SNS 層は mint 時に `artifact_id` を指定する必要があり、事前に Artifact を登録しておく。
- 物理作品・URL 作品の両方を登録可能。

## 影響範囲

- **変更対象**:
  - `config/routes.rb`
  - `app/controllers/artifacts_controller.rb`（新規）
  - `spec/requests/artifacts_spec.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: 新規エンドポイント

## スキーマ変更

なし

## 実装ステップ

1. routes
   ```ruby
   resources :artifacts, only: [:create, :show]
   ```
2. コントローラ
   ```ruby
   # app/controllers/artifacts_controller.rb
   # TODO: 認証は将来拡張（別基盤）
   class ArtifactsController < ApplicationController
     def show
       artifact = Artifact.find(params[:id])
       render(json: serialize(artifact))
     end

     def create
       artifact = Artifact.create!(artifact_params)
       render(json: serialize(artifact), status: :created)
     end

     private

     def artifact_params
       params.expect(artifact: [:user_id, :title, :location_kind, :location_url])
     end

     def serialize(artifact)
       {
         id: artifact.id,
         user_id: artifact.user_id,
         title: artifact.title,
         location_kind: artifact.location_kind,
         location_url: artifact.location_url,
         created_at: artifact.created_at.iso8601,
       }
     end
   end
   ```
3. Request spec
   - 物理 Artifact の作成（`location_kind: "physical"`, `location_url: nil`）
   - URL Artifact の作成（`location_kind: "url"`, `location_url: "https://..."`）
   - 404 / 422 エラーパターン

## テスト要件

- POST 正常系（physical / url 両方）
- POST 異常系: `location_kind` 不正、`user_id` 不存在
- GET 正常系 / 404

## 技術的な補足

- `belongs_to :user` により `user_id` 未指定 or 不存在は validation で捕捉される。
  Rails 標準では `user_id` 不存在は `ActiveRecord::InvalidForeignKey` になるため、
  コントローラ側で `User.find(params[:artifact][:user_id])` を先に呼んでおくと整ったエラーになる（MVP は標準挙動で許容）。

## 非スコープ

- 一覧 API
- 更新・削除 API

## 受け入れ基準

- [ ] POST / GET が仕様通りに動く
- [ ] RSpec / RuboCop が通る
