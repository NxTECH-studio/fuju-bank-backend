# 19: ArtistChannel 骨組み

> 依存: #09

## 概要

Solid Cable 上で動く `ArtistChannel` を実装する。作家 HUD が `artist_id` を指定して subscribe する。

## 背景・目的

- 作家 HUD にリアルタイムで「+15 ふじゅ〜」等を通知する経路を作る。
- MVP では `artist_id` のみで identify する簡易接続。公開鍵署名検証は将来。

## 影響範囲

- **変更対象**:
  - `app/channels/application_cable/connection.rb`（新規 / Rails デフォルト）
  - `app/channels/application_cable/channel.rb`（新規 / Rails デフォルト）
  - `app/channels/artist_channel.rb`（新規）
  - `spec/channels/artist_channel_spec.rb`（新規）
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
     # MVP: 認証は ArtistChannel#subscribed 内で artist_id を検証する簡易方式
   end
   ```
2. `app/channels/application_cable/channel.rb`
   ```ruby
   class ApplicationCable::Channel < ActionCable::Channel::Base
   end
   ```
3. `app/channels/artist_channel.rb`
   ```ruby
   # Artist 単位のリアルタイム配信チャネル。
   # 接続時に artist_id を受け取り、該当 Artist の broadcast を stream する。
   #
   # TODO: 認証は将来拡張（HUD の public_key で署名検証）
   class ArtistChannel < ApplicationCable::Channel
     def subscribed
       artist = Artist.find_by(id: params[:artist_id])
       if artist.nil?
         reject
       else
         stream_for artist
       end
     end

     def unsubscribed
       # no-op
     end
   end
   ```
4. spec
   ```ruby
   # spec/channels/artist_channel_spec.rb
   require "rails_helper"

   RSpec.describe ArtistChannel, type: :channel do
     let!(:artist) { create(:artist) }

     it "subscribes with valid artist_id" do
       subscribe(artist_id: artist.id)
       expect(subscription).to be_confirmed
       expect(subscription).to have_stream_for(artist)
     end

     it "rejects subscription with unknown artist_id" do
       subscribe(artist_id: 999999)
       expect(subscription).to be_rejected
     end
   end
   ```

## テスト要件

- 有効な `artist_id` で subscribe できる
- 無効な `artist_id` で reject される
- `stream_for(artist)` が張られている

## 技術的な補足

- `stream_for(artist)` は Rails が `ArtistChannel:<gid://app/Artist/1>` のようなストリーム名を自動生成する。
  broadcast 側（#20）は `ArtistChannel.broadcast_to(artist, payload)` で同じストリームに送る。
- Solid Cable を使うため追加設定は不要（`config/cable.yml` 既定）。
- `ApplicationCable::Connection#connect` を実装していないため、identified_by は使わない。
  認証導入時にここを書き換える（TODO）。
- RSpec の `subscribe` / `have_stream_for` は `rspec-rails` の Channel spec helper。

## 非スコープ

- 認証（public_key 署名）
- broadcast 発火 → #20
- ack / 再送機構

## 受け入れ基準

- [ ] `ArtistChannel` が subscribe / reject の両方を正しく扱う
- [ ] RSpec / RuboCop が通る
