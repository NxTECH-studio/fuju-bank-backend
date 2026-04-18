# 19: UserChannel 骨組み

> 依存: #09

## 概要

Solid Cable 上で動く `UserChannel` を実装する。作家 HUD が `user_id` を指定して subscribe する。

## 背景・目的

- 作家 HUD にリアルタイムで「+15 ふじゅ〜」等を通知する経路を作る。
- MVP では `user_id` のみで identify する簡易接続。公開鍵署名検証は将来。

## 影響範囲

- **変更対象**:
  - `app/channels/application_cable/connection.rb`（新規 / Rails デフォルト）
  - `app/channels/application_cable/channel.rb`（新規 / Rails デフォルト）
  - `app/channels/user_channel.rb`（新規）
  - `spec/channels/user_channel_spec.rb`（新規）
  - `config/cable.yml`（既存。Solid Cable 設定確認のみ）
- **破壊的変更**: なし
- **外部層への影響**: 新規チャネル公開

## スキーマ変更

なし（Solid Cable のスキーマは `db/cable_schema.rb` として別管理）

## 実装ステップ

1. `app/channels/application_cable/connection.rb`
   ```ruby
   # TODO: 認証は将来拡張（public_key 署名検証）
   class ApplicationCable::Connection < ActionCable::Connection::Base
     # MVP: 認証は UserChannel#subscribed 内で user_id を検証する簡易方式
   end
   ```
2. `app/channels/application_cable/channel.rb`
   ```ruby
   class ApplicationCable::Channel < ActionCable::Channel::Base
   end
   ```
3. `app/channels/user_channel.rb`
   ```ruby
   # User 単位のリアルタイム配信チャネル。
   # 接続時に user_id を受け取り、該当 User の broadcast を stream する。
   #
   # TODO: 認証は将来拡張（HUD の public_key で署名検証）
   class UserChannel < ApplicationCable::Channel
     def subscribed
       user = User.find_by(id: params[:user_id])
       if user.nil?
         reject
       else
         stream_for user
       end
     end

     def unsubscribed
       # no-op
     end
   end
   ```
4. spec
   ```ruby
   # spec/channels/user_channel_spec.rb
   require "rails_helper"

   RSpec.describe UserChannel, type: :channel do
     let!(:user) { create(:user) }

     it "subscribes with valid user_id" do
       subscribe(user_id: user.id)
       expect(subscription).to be_confirmed
       expect(subscription).to have_stream_for(user)
     end

     it "rejects subscription with unknown user_id" do
       subscribe(user_id: 999999)
       expect(subscription).to be_rejected
     end
   end
   ```

## テスト要件

- 有効な `user_id` で subscribe できる
- 無効な `user_id` で reject される
- `stream_for(user)` が張られている

## 技術的な補足

- `stream_for(user)` は Rails が `UserChannel:<gid://app/User/1>` のようなストリーム名を自動生成する。
  broadcast 側（#20）は `UserChannel.broadcast_to(user, payload)` で同じストリームに送る。
- Solid Cable を使うため追加設定は不要（`config/cable.yml` 既定）。
- `ApplicationCable::Connection#connect` を実装していないため、identified_by は使わない。
  認証導入時にここを書き換える（TODO）。
- RSpec の `subscribe` / `have_stream_for` は `rspec-rails` の Channel spec helper。

## 非スコープ

- 認証（public_key 署名）
- broadcast 発火 → #20
- ack / 再送機構

## 受け入れ基準

- [ ] `UserChannel` が subscribe / reject の両方を正しく扱う
- [ ] RSpec / RuboCop が通る
