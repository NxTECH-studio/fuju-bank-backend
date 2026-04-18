# 14: GET /users/:id エンドポイント（残高取得）

> 依存: #01, #09

## 概要

User 情報と残高（`balance_fuju`）を返す API。作家 HUD の起動時・残高画面で使う。

## 背景・目的

- HUD 起動直後に残高を取得する用途。
- ActionCable 接続前の初期状態の取得にも使う。

## 影響範囲

- **変更対象**:
  - `app/controllers/users_controller.rb`（#13 で作成したものに `show` アクション追加）
  - `spec/requests/users_spec.rb`（#13 と同ファイル）
- **破壊的変更**: なし
- **外部層への影響**: 新規エンドポイント公開

## スキーマ変更

なし

## 実装ステップ

1. コントローラに `show` を追加
   ```ruby
   def show
     user = User.includes(:account).find(params[:id])
     render(json: serialize(user))
   end
   ```
2. routes は #13 で `resources :users, only: [:create, :show]` に含まれる
3. Request spec
   ```ruby
   describe "GET /users/:id" do
     let!(:user) { create(:user) }

     it "returns balance_fuju" do
       get "/users/#{user.id}"
       expect(response).to have_http_status(:ok)
       expect(response.parsed_body).to include("id" => user.id, "balance_fuju" => 0)
     end

     it "returns 404 when missing" do
       get "/users/999999"
       expect(response).to have_http_status(:not_found)
       expect(response.parsed_body.dig("error", "code")).to eq("NOT_FOUND")
     end
   end
   ```

## テスト要件

- 正常系: 200 + `balance_fuju`
- 異常系: 存在しない ID で 404 + `NOT_FOUND`
- `includes(:account)` で N+1 が発生しないことを bullet で確認

## 技術的な補足

- `find` は `ActiveRecord::RecordNotFound` を投げ、#01 の rescue_from で 404 になる。
- `includes(:account)` は account の balance_fuju 参照で N+1 を避けるため。

## 非スコープ

- 認証
- transactions（履歴）は #18 で別エンドポイント

## 受け入れ基準

- [ ] `GET /users/:id` で 200 + 残高が返る
- [ ] 存在しない ID で 404 + `NOT_FOUND`
- [ ] RSpec / RuboCop が通る
- [ ] bullet 警告なし
