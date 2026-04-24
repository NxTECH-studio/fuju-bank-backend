# STEP 07: 動作確認（手動 E2E）

- **前提 STEP**: [`06-payments-qr-controller.md`](./06-payments-qr-controller.md)（エンドポイントが動作する）
- **次の STEP**: なし（本 STEP が最終）
- **全体像**: [`00-overview.md`](./00-overview.md)

## 目的

API 単体だけでなく、コマンドレベルで一連の動作を確認する。QR 生成 → 検証 → 送金 → 残高更新の流れが E2E で成立することを確かめる。

## 作業内容

1. `make console` で Store / User / 初期残高を用意
2. `Qr::Signer.call(store: store)` で QR URI を生成し、クエリをパースして署名を取り出す
3. `curl` で `POST /payments/qr` を叩き 200 を確認
4. `Account` の残高が両側で正しく増減していることを確認
5. （余力があれば）ActionCable を WebSocket クライアントで購読し、broadcast を確認（※ MVP では store 側 broadcast は未対応、from_user 側 broadcast も現状未対応 = 期待挙動として OK）

## 受け入れ基準

- 手順を README 化せず、この STEP は「一度成功を確認したら完了」で良い（ドキュメント化は不要）

## テスト観点

- 自動テストは追加不要（`05` / `06` の spec でカバー済み）
- 手動確認の結果、`05` / `06` の想定外挙動があれば該当 STEP のドキュメントに追記して PR を出し直す
