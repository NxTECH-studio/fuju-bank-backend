# 16: POST /ledger/mint エンドポイント

> 依存: #01, #03, #11

## 概要

ふじゅ〜発行 API。マイニング層（2 層目）が呼び出す中核エンドポイント。

## 背景・目的

- マイニング層が「Artifact X に Artist Y が N ふじゅ〜を受けるに値する滞留をした」と通知する。
- べき等性が必須（ネットワーク不安定）。
- `metadata` に滞留秒数や視線強度を含め、後で分析できるようにする。

## 影響範囲

- **変更対象**:
  - `config/routes.rb`
  - `app/controllers/ledger_controller.rb`（新規）
  - `spec/requests/ledger_mint_spec.rb`（新規）
- **破壊的変更**: なし
- **外部層への影響**: マイニング層との契約となる重要 API

## スキーマ変更

なし

## 実装ステップ

1. routes
   ```ruby
   post "ledger/mint", to: "ledger#mint"
   ```
2. コントローラ
   ```ruby
   # app/controllers/ledger_controller.rb
   # TODO: 認証は将来拡張（マイニング層からの署名検証など）
   class LedgerController < ApplicationController
     include Idempotent

     def mint
       artifact = Artifact.find(mint_params[:artifact_id])
       artist = Artist.find(mint_params[:artist_id])

       tx = Ledger::Mint.call(
         artifact: artifact,
         artist: artist,
         amount: mint_params[:amount].to_i,
         idempotency_key: idempotency_key!,
         metadata: mint_params[:metadata].to_h,
         occurred_at: parse_occurred_at(mint_params[:occurred_at]),
       )

       render(json: serialize(tx), status: :ok)
     end

     private

     def mint_params
       params.expect(ledger: [:artifact_id, :artist_id, :amount, :occurred_at, metadata: {},])
     end

     def parse_occurred_at(value)
       value.present? ? Time.zone.parse(value) : Time.current
     end

     def serialize(tx)
       {
         id: tx.id,
         kind: tx.kind,
         artifact_id: tx.artifact_id,
         idempotency_key: tx.idempotency_key,
         metadata: tx.metadata,
         occurred_at: tx.occurred_at.iso8601,
         created_at: tx.created_at.iso8601,
       }
     end
   end
   ```
3. `Idempotent` concern は #03 で作成済みの想定（`idempotency_key!` メソッドを提供）

## テスト要件

- 正常系: 201/200 で記帳される。Artist 残高 +N、system_issuance 残高 -N。
- 冪等性: 同じ `Idempotency-Key` で 2 回 POST しても作成は 1 回。2 回目は 200 で既存を返す。
- 異常系:
  - `Idempotency-Key` 未指定 → 400（#03 の concern が担当）
  - `amount = 0` / 負値 → 422
  - `artifact_id` 不存在 → 404
  - `artist_id` 不存在 → 404
- `metadata` にネストした Hash を渡して JSONB にそのまま保存される

## 技術的な補足

- `metadata` を strong parameters で許可するため `metadata: {}` を使う（Rails 8 の `params.expect` 表記）。
- `occurred_at` の形式は ISO8601 推奨（例: `"2026-04-17T12:34:56+09:00"`）。
- HTTP ステータス: 新規作成時 `201` / 冪等重複時 `200` の使い分けは MVP では統一 `200` とする（分けるのは将来拡張）。
  → シンプルさ優先。
- 認証は TODO コメントとして明記。

## 非スコープ

- 認証
- broadcast → #20

## 受け入れ基準

- [ ] `POST /ledger/mint` が仕様通り動く
- [ ] 冪等性が保証される（unique violation を含む）
- [ ] 422 / 404 / 400 のエラー分類が正しい
- [ ] RSpec / RuboCop が通る
