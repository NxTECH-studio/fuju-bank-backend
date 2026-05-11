# users-search-cross-service-identity

## 概要

`GET /users/search` が staging で空配列しか返さない問題の **根本対処** の方針決定。
[users-search-by-public-id.md](./users-search-by-public-id.md) で検索キーを `public_id` 前方一致に
切り替えたが、**`bank.users.public_id` が大半 NULL** のため検索ヒットが極端に少ないという
症状が継続している。

本タスクは「クロスサービスの identity をどこに置き、どう同期するか」の方針決定を扱い、
合意後に実装タスクへ分割する（=本タスクは spec/decision、コード変更は含まない）。

## 背景・現状の問題

### 症状

```
2026-05-10 17:00 GET https://api.fujupay.app/users/search?q=tokyo → {"users":[]}
```

クライアント側からの動作確認で「どの ID で叩いてもヒットしない」と報告されている。

### 根本原因: `bank.users.public_id` がほぼ未充填

`bank.users.public_id` への入り口は `POST /users/me` (`UsersController#upsert_me`) からの
`UserProvisioner.call(public_id:)` のみ (`app/services/user_provisioner.rb:5,31`)。
これに 2 つの問題がある:

1. **クライアント任せ**: Android が `POST /users/me` の payload に `public_id` を含めない限り
   保存されない。AuthCore JWT の claims には `public_id` が含まれていないため
   (`fuju-system-authentication/pkg/crypto/jwt.go` の `Claims` は `Type / TokenFamily / Scope / MFAVerified` のみ)、
   サーバ側が JWT から自動補完できない。
2. **`UserProvisioner` が既存ユーザーを更新しない** (`app/services/user_provisioner.rb:17-18`):
   ```ruby
   existing_user = User.find_by(external_user_id: @external_user_id)
   return existing_user if existing_user  # ← public_id 引数は使われない
   ```
   AuthCore で `public_id` を変更しても bank に伝播しない（実質バグ）。

加えて、AuthCore 側に **そもそも user search エンドポイントが無い**。既存は:

- `GET /v1/user/profile` — self のみ（Bearer 必須）
- `GET /v1/users/lookup?provider=x|youtube&q=...` — X/YouTube ハンドルの existence チェック専用

bank が AuthCore に問い合わせて補完する経路は現状存在しない。

### 設計上の論点

`fuju-system-authentication/docs/api-summary.md` で AuthCore は
**「identity provider であって user directory ではない」** と明記されている。
一方で bank が `users.public_id` を持っている時点で identity の複製になっており、
責務境界をどう引くかが本タスクの核心。

「アカウントは共通基盤だから bank に user が無い状況はありえない」という方向に倒すなら
identity を全サービスに fan-out する設計（A）に寄せ、
「AuthCore が directory として一次応答する」方向に倒すなら委譲設計（B）に寄せる。

## 方針候補

| 案 | 概要 | 利点 | 欠点 |
|---|---|---|---|
| **A. eager fan-out** | AuthCore で register した瞬間に webhook / event で bank に「未ログイン」状態のユーザーを作る | `bank.users` が常に完全 / 検索が素直に動く / `public_id` 変更も即時反映可能 / 「bank にユーザーが居ない」状態が原理的に消える | AuthCore が下流を知る必要（`docs/api-summary.md` の方針を更新）/ 障害時の reconciliation 設計が別途必要 / 新サービス追加で購読が増える |
| **B. AuthCore へ委譲（推奨）** | AuthCore に `GET /v1/users/search`（Basic Auth, `public_id` 前方一致）を追加。bank の `users#search` は AuthCore 結果を返す。`bank.users.public_id` は当面キャッシュ扱い | 責務境界が明確（AuthCore = directory）/ 検索のたびに最新が返る / 識別子複製の段階的解消 | AuthCore に新エンドポイント / `api-summary.md` の文言更新 / 検索のたびに service-to-service HTTP コスト（既に introspect で 1 hop 発生中） |
| **C. lazy 強化** | 現状維持で `UserProvisioner` の更新バグを修正、クライアントは `POST /users/me` に `public_id` を必ず含める | 変更最小 | bank.users が更新されるのは「bank API を叩いた時」だけ / 未ログインユーザー問題は残る / 表面的な対症療法 |
| **D. introspection 経由 lazy 補完** | `JwtAuthenticatable#current_user` に introspect コール経路を追加し、`Authcore::IntrospectionResult#username` (= `PublicID`) から遅延補完 | 認証の延長で実装可能 / AuthCore 側の追加実装ゼロ | 参照系全リクエストに introspect コスト / 「bank API を叩いた時」しか同期しないのは C と同根 |

## 推奨

**B + C の最小部分**。

- 検索の正解性は AuthCore に委譲（B）
- 並行して `UserProvisioner` の「既存ユーザーで `public_id` が更新されないバグ」を修正（C の最小部分）
- `bank.users.public_id` は当面残すが、検索の一次ソースは AuthCore に倒す
  → 将来 `bank.users.public_id` を削除する余地を残す

A はインフラ追加コストが大きい。D は責務漏れがあるので避ける。

## 決定すべき事項

エンジニア判断が必要:

- [ ] **採用方針**: B / A / C / D / 別案 のどれにするか
- [ ] **B 採用時の細部**:
  - [ ] AuthCore のレスポンスに `icon_url` を含めるか（AuthCore には `IconURL` カラムあり、現状 bank は常に null 返却）
  - [ ] `bank.users.public_id` を将来削除するか / キャッシュとして残すか
  - [ ] 自己除外を AuthCore 側で実装するか（caller 識別が必要）/ bank 側で `external_user_id` ベースに後段フィルタするか
  - [ ] 「bank に account がまだ無いユーザー」を検索結果に出すか
    - 出す → 送金時に lazy provision でカバー（`Ledger::Transfer` の前段で `UserProvisioner` を呼ぶ追加実装が要る）
    - 出さない → bank `users` テーブルとの inner join 相当を bank 側で実施

## 影響範囲

### B 採用時

- `fuju-system-authentication`
  - `GET /v1/users/search?q=&limit=` 新設（Basic Auth）
  - ハンドラ + ユースケース + リポジトリの `SearchByPublicIDPrefix` メソッド追加
  - `docs/api-summary.md` の方針文言更新（directory 機能を限定的に解禁する旨）
- `bank/fuju-bank-backend`
  - `app/services/authcore/user_search_client.rb`（仮）新設
  - `UsersController#search` を AuthCore 委譲版に置換
  - `serialize_search_hit` の `icon_url` を実値に
  - `app/services/user_provisioner.rb` の更新バグ修正（C の最小部分）
  - `spec/requests/users_search_spec.rb` の前提変更（WebMock/VCR で AuthCore モック）
  - `README.md` API 一覧の更新
- `bank/fuju-bank-app` (別リポ、別タスク)
  - `UserSearchApi` 側の変更は不要（レスポンス形は維持）

### A 採用時

上記に加えて:
- AuthCore に webhook 配信基盤（永続化 + リトライ + 署名）
- bank に webhook 受信エンドポイント + provisioning ハンドラ
- reconciliation ジョブ（fan-out 失敗の補修）

## 後続タスクの分割案

合意後に以下に分割する:

### B 採用シナリオ
- `authcore-NN-users-search-endpoint.md` — AuthCore 側に検索 API 追加（fuju-system-authentication 側で起票）
- `bank-NN-users-search-authcore-delegation.md` — bank 側を委譲版に置き換え
- `bank-NN-user-provisioner-update-fix.md` — `UserProvisioner` の既存更新バグ修正

### A 採用シナリオ
- AuthCore webhook 配信基盤
- bank の webhook 受信 + provisioning
- reconciliation ジョブ

## 関連タスク

- [users-search-by-public-id.md](./users-search-by-public-id.md) — 完了。検索キーを `public_id` 前方一致に切り替えた前段
- [server-bank-22-recipient-resolution-api.md](./server-bank-22-recipient-resolution-api.md) — `/users/search` の元タスク
- [b2-users-lazy-provisioning.md](./b2-users-lazy-provisioning.md) — 完了。現在の lazy provisioning の経緯
