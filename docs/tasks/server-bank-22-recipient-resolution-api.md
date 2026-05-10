# server-bank-22: 受取人解決 API（送金先 表示名検索）

> 本タスクは Rails 製の **fuju-bank-backend** リポジトリ側で実施する作業の計画書。
> 計画書ファイル自体はクライアント計画書 `docs/tasks/client-bank-22-money-transfer.md` と
> 一元参照したいため、本リポジトリ（`fuju-bank-app`）の `docs/tasks/` に置く。
> 実装着手時にバックエンドリポジトリへ Notion タスクと併せて移送する想定。

## 概要

クライアント側送金フロー（`client-bank-22`）が成立するために必要な、
**「ユーザー入力（表示名）→ bank 内部 user id（候補リスト）」を解決する公開 API** を
fuju-bank-backend に追加する。クライアントはこの API のレスポンスから候補をユーザーに選択させ、
選んだ候補の `id` を `POST /ledger/transfer` の `to_user_id` に詰めて送金する。

**方針転換（2026-05-10）**: 当初は `public_id` 完全一致 API（候補 1）を推奨していたが、
クライアント側 UX 方針確定（「表示名で送金先を絞り込む」）に伴い、**表示名部分一致検索 API
（候補 3）** に推奨方針を切り替えた。経緯は §「採用方針の変遷（履歴）」参照。

## 背景・目的

- `client-bank-22` の最大ブロッカー: クライアントが「表示名で送金先を決める」UX を
  組もうとしても、bank 側に **表示名から bank の `users.id`（bigint）の候補を返す検索 API がない**。
- 既存 API の状況:
  - `GET /v1/user/profile`（AuthCore）: **自分自身** の AuthCore プロフィールしか取れない。
  - `GET /users/me`（bank）: **自分自身** の bank プロフィール（`balance_fuju` 等）。
  - `GET /users/:id`（bank）: bank の **内部主キー（bigint）を既に知っている前提** の API。
    クライアントは他人の bank id を知る経路がない。
  - 表示名 (`users.name`) は public_id のような一意制約がなく、現状検索 API もない。
- そのため、**任意の他ユーザーを表示名で検索する公開 API** を追加する必要がある。
- `POST /ledger/transfer` 自体は既に存在し、送信元・宛先の残高更新は 1 トランザクションで
  ledger_transactions INSERT + users.balance_fuju UPDATE が走る前提なので、本タスクの
  スコープは **検索 API の新設のみ**。送金本体は触らない。

## スコープ

### 含む

- 表示名検索エンドポイント 1 本の新設（`GET /users/search`）
- レスポンス DTO 設計（配列レスポンス、各要素 `id` / `public_id` / `name` / `icon_url`）
- DB / マイグレーション: `users.public_id` 冗長カラムの追加（API レスポンスで public_id 末尾4桁を返すために必要）+ `users.display_name` の検索用インデックス（pg_trgm or LIKE 用 btree）
- 認証要件・レート制限・プライバシー設計（**enumeration 対策強化**）
- request spec（RSpec）と controller spec（部分一致 / 上限件数 / 自分除外 / 認証 / レート制限）
- README / API 仕様書（バックエンド側）への追記
- クライアント側 (`UserSearchApi.searchByDisplayName(query)` 想定) との DTO 整合確認

### 含まない

- `POST /ledger/transfer` 本体の改修（既存の挙動を維持）
- 表示名 (`users.name`) のユニーク制約導入（仕様上 OK = 重複可。UX 側で public_id 末尾4桁で識別）
- フォロー / 連絡先のような新規ドメイン概念の追加
- AuthCore (`fuju-system-authentication`) 側の API 追加（候補 2 を採用しない前提）
- `public_id` 完全一致 API（候補 1、本タスクから外す。将来必要になれば別タスクで追加）

## 採用方針: 候補 3（表示名部分一致検索）

クライアント計画書 §「採用するフロー全体図」で確定した UX:

> 入力（最低 2 文字）→ `GET /users/search?q={表示名}` で部分一致候補を取得
> → 候補リスト「丸アバター + 表示名 + public_id 末尾4桁」を縦並び
> → 候補タップで bottom sheet 確認モーダル

このため、サーバ側の責務は:

1. クエリ文字列で `users.display_name` を **部分一致 or 前方一致** で検索（方針は Open Questions）
2. 上限 N 件（10〜20 件、運用で調整）に制限
3. 自分自身を結果から除外（API 側または UI 側の責務切り分けは Open Questions）
4. 各結果に `id` / `public_id` / `name` / `icon_url` を返す
5. enumeration 攻撃対策のため、**認証必須 / 厳しめレート制限 / クエリ最低 2 文字 / 個人情報を返さない / 異常検知のためのロギング** を徹底

## API 仕様案

### エンドポイント

```
GET /users/search?q={表示名}&limit={n}
```

- 認証: AuthCore JWT（access_token Bearer）必須。bank API のデフォルト Auth プラグイン経路。
- introspection: 通常の bank API と同じく introspection で `active=true` を要求。
- レート制限: 後述（**従来より厳しめ**）。

### リクエストパラメータ

| 名前 | 型 | 必須 | 備考 |
|---|---|---|---|
| `q` | string | yes | 検索クエリ（表示名）。**最低 2 文字、最大 64 文字**。空白前後トリム。 |
| `limit` | integer | no | 結果上限。デフォルト 10、最大 20。 |

### レスポンス

#### 200 OK

```json
{
  "users": [
    {
      "id": 1234,
      "public_id": "alice",
      "name": "アリス",
      "icon_url": "https://cdn.fujupay.app/icons/abc.png"
    },
    {
      "id": 5678,
      "public_id": "alice2024",
      "name": "アリス",
      "icon_url": null
    }
  ]
}
```

| フィールド | 型 | nullable | 備考 |
|---|---|---|---|
| `users` | array | no | 検索結果。0..N 件（N <= limit） |
| `users[].id` | integer (bigint) | no | bank 内部 user id。`POST /ledger/transfer` の `to_user_id` に渡す |
| `users[].public_id` | string | no | AuthCore の public_id。UX 側で末尾4桁を表示し、表示名重複時の識別に使う |
| `users[].name` | string | yes | bank 側 `users.name`（未設定なら null。検索ヒット条件は基本的に name not null）|
| `users[].icon_url` | string (URL) | yes | AuthCore の icon_url（未設定なら null）|

> `email` / `mfa_enabled` / `balance_fuju` / `created_at` / `last_sign_in_at` などは
> プライバシー観点で **返さない**。

#### 422 Unprocessable Entity

```json
{ "error": { "code": "VALIDATION_FAILED", "message": "q must be at least 2 characters" } }
```

- `q` パラメータ欠落
- `q` が 1 文字以下 / 64 文字超
- `limit` が 1 未満 / 20 超

#### 401 Unauthorized

- `UNAUTHENTICATED`: access_token 欠落 / 無効
- `TOKEN_INACTIVE`: introspection で `active=false`

#### 429 Too Many Requests

```json
{ "error": { "code": "RATE_LIMIT_EXCEEDED", "message": "Too many search requests" } }
```

- 後述レート制限超過時。

### サーバ実装の流れ（疑似コード）

```ruby
# app/controllers/users_controller.rb
def search
  q = params.require(:q).to_s.strip
  validate_q!(q)  # 422 on invalid (length 2..64)

  limit = (params[:limit] || 10).to_i.clamp(1, 20)

  scope = User.where("display_name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(q)}%")
              .where.not(id: current_user.id)  # 自分除外（API 側）
              .order(:id)
              .limit(limit)

  # ロギング（異常検知用）
  AuditLog.create!(
    actor: current_user,
    action: "users.search",
    payload: { q_length: q.length, hit_count: scope.size }
  )

  render json: { users: scope.map { |u| serialize_search_hit(u) } }
end
```

> 注:
> - `users.public_id` カラム化は本タスクの Phase 1 で実施。
> - `users.display_name` のインデックス: pg_trgm + GIN を入れるのが理想。LIKE 検索のみで十分なら
>   `text_pattern_ops` の btree でも可。クエリパターン（前方一致 vs 部分一致）で決める。

## DB / マイグレーション

### 1. `users.public_id` 冗長カラム

- API レスポンスで `public_id` を返すために、bank 側に AuthCore の `public_id` を冗長保持する。
- 既存ユーザーには backfill ジョブで AuthCore から取得して埋める。
- `POST /users/me`（lazy provision）で AuthCore レスポンスから `public_id` を保存するように変更。
- ユニーク制約付与（AuthCore 側で一意保証されているため）。

### 2. `users.display_name` の検索用インデックス

部分一致検索の性能を担保するため、いずれかを採用:

- **案 A: pg_trgm + GIN インデックス**（部分一致に強い、推奨）
  ```ruby
  enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')
  add_index :users, :display_name, using: :gin, opclass: { display_name: :gin_trgm_ops }
  ```
- **案 B: btree + text_pattern_ops**（前方一致のみ、軽量）
  ```ruby
  add_index :users, :display_name, opclass: :text_pattern_ops
  ```

→ 部分一致 / 前方一致のどちらを採用するかは Open Questions 1 で確定。

## 認証・プライバシー（enumeration 対策強化）

### 認証要件

- **必須**: AuthCore JWT（Bearer）+ introspection で `active=true`。
- 未認証ユーザーには公開しない。検索クローラ / 名前収集を防ぐため。

### レート制限（**従来より厳しめ**）

- **per user**: 30 req / minute
- **per IP**: 60 req / minute
- 既存の Rack::Attack（または rack-attack）設定にエンドポイント別 throttler を追加。
- 超過時は `429 RATE_LIMIT_EXCEEDED` を返す。
- 候補 1 採用時の数値（per user 60/min, per IP 120/min）から **半分に絞った**。
  表示名検索は public_id 完全一致と違って enumeration リスクが高いため。

### プライバシー観点

- **返さない情報**: email, balance, mfa_enabled, created_at, last_sign_in_at 等。
- **返す情報**: 送金 UI で必要最小限（id / public_id / name / icon_url）。
- **クエリ最低 2 文字**: 1 文字では結果セットが大きくなりすぎ、enumeration リスクが上がるため
  サーバ側で **422 拒否**。
- **異常検知ロギング**: `AuditLog` に `actor`, `q.length`（クエリ文字列そのものはログしない）, `hit_count`,
  `timestamp` を記録。短時間に大量検索する actor を後追い特定できるようにする。
- **タイミング攻撃対策**: 0 件 / N 件のレスポンス時間揃えは優先度低（MVP では入れない）。

### 自分自身の除外

- **第一案: API 側で除外**（推奨。`where.not(id: current_user.id)` を controller で必ず適用）。
  - クライアント実装ミスでも漏れない。
- **第二案: UI 側で除外**（クライアント `UserRepository.searchByDisplayName` で actor の id を弾く）。
  - サーバの責務がシンプルになる。
- → Open Questions 3 で確定。**当面は API 側で除外し、UI 側でも二重チェックするのが安全**。

## 表示名重複時の振る舞い

- 表示名は重複可（仕様上 OK）。検索結果は **重複したまま全件返す**。
- UX 側は「表示名 + アイコン + public_id 末尾4桁」で候補を識別させる（クライアント計画書参照）。
- ヒット件数が limit を超えた場合は **id 昇順で先頭 N 件のみ返す**（`created_at` 順や類似度順は将来の改善）。

## 影響範囲

- **追加**: `app/controllers/users_controller.rb#search`、`config/routes.rb` への 1 行追加
- **追加（DB）**:
  - `users.public_id` カラム追加マイグレーション + unique index
  - `users.display_name` の検索用インデックス（pg_trgm GIN または btree text_pattern_ops）
  - 既存ユーザーには backfill ジョブで AuthCore から `public_id` を埋める
- **変更**: `POST /users/me`（lazy provision）で AuthCore レスポンスから `public_id` を保存
- **変更（rack-attack）**: search エンドポイントの throttle ルール追加（per-user 30/min, per-IP 60/min）
- **追加（AuditLog）**: `users.search` アクションの記録
- **変更（README）**: API 一覧表に `GET /users/search` を追記

## バリデーション / エラー

| ケース | HTTP | code | 備考 |
|---|---|---|---|
| `q` 欠落 | 422 | `VALIDATION_FAILED` | |
| `q` が 1 文字以下 / 64 文字超 | 422 | `VALIDATION_FAILED` | enumeration 対策の最低 2 文字 |
| `limit` が 1 未満 / 20 超 | 422 | `VALIDATION_FAILED` | clamp 後に超過していたら拒否 |
| 該当ユーザー不在（0 件ヒット） | 200 | （正常） | `{ "users": [] }` を返す。404 ではない |
| access_token 欠落 / 無効 | 401 | `UNAUTHENTICATED` | |
| introspection inactive | 401 | `TOKEN_INACTIVE` | |
| レート制限超過 | 429 | `RATE_LIMIT_EXCEEDED` | per-user 30/min, per-IP 60/min |
| 自分自身がヒット | 200 | （正常） | API 側で除外して結果に含めない |

## テスト方針（RSpec）

### request spec（`spec/requests/users_search_spec.rb`）

```ruby
describe "GET /users/search" do
  context "with valid query (2 chars)" do
    it "returns matching users with public profile fields"
    it "returns at most :limit users (default 10, max 20)"
    it "excludes the caller from results"
    it "returns empty array when no match"
    it "returns multiple users when display_name is duplicated"
  end

  context "partial match" do
    it "matches substring (e.g., 'リス' hits 'アリス')"
    # or: it "matches prefix only (depending on Open Question 1)"
  end

  context "validation" do
    it "returns 422 when q is missing"
    it "returns 422 when q is 1 character"
    it "returns 422 when q is over 64 characters"
    it "returns 422 when limit is over 20"
  end

  context "without access token" do
    it "returns 401 UNAUTHENTICATED"
  end

  context "when introspection returns inactive" do
    it "returns 401 TOKEN_INACTIVE"
  end

  context "rate limit" do
    it "returns 429 after the per-user threshold (30/min)"
    it "returns 429 after the per-IP threshold (60/min)"
    # 単体で動かしづらいので skip フラグ可
  end

  context "audit log" do
    it "records the search action with q.length and hit_count"
  end
end
```

### model spec / migration spec

- `users.public_id` の uniqueness 制約
- `POST /users/me` での public_id 書き込み（既存 spec の拡張）
- `users.display_name` のインデックス存在確認

### 副次: 既存スイートへの影響

- `POST /users/me` を変えるなら既存 request spec の更新が必要
- `POST /ledger/transfer` 関連 spec への影響はないはず（`to_user_id` は数値で受ける既存挙動のまま）

## 完了条件

1. `GET /users/search?q=xxx&limit=n` が main にマージされ、staging 環境（`api.fujupay.app`）で動作
2. 既存の `POST /users/me` が AuthCore レスポンスから `public_id` を保存するように更新済み
3. 既存ユーザー全員に対して backfill 完了（`users.public_id` が NULL のレコードがゼロ）
4. `users.display_name` に検索用インデックスが追加されている
5. RSpec が green、新規 request spec も追加済み
6. レート制限が rack-attack に組み込まれ、超過時 429 を返すことを手動確認
7. AuditLog に `users.search` レコードが作成されることを手動確認
8. バックエンド README の API 一覧表に追記
9. クライアント `client-bank-22` 側で `UserSearchApi.searchByDisplayName(query)` を呼んで動作確認できる状態
   （= フロント実装の Phase 2 がアンブロックされる）

## Open Questions

1. **部分一致 vs 前方一致**
   - 部分一致（`%q%`）: UX が直感的（「リス」で「アリス」がヒット）。pg_trgm + GIN が必要、ややコスト高。
   - 前方一致（`q%`）: 実装軽量、btree text_pattern_ops で十分。
   - **推奨**: 部分一致（pg_trgm GIN）。表示名は短く、前方一致だと「@」プレフィックス文化のないユーザーには使いづらい。
2. **ヒット件数上限（limit のデフォルト / max）**
   - 推奨: デフォルト 10、max 20。運用見て調整。
3. **自分を結果から除外する層（API か UI か）**
   - 推奨: **API 側で必ず除外**（`where.not(id: current_user.id)`）+ UI 側でも二重チェック。
   - 理由: クライアント実装ミスでも自分宛の送金候補が出ないことを保証。
4. **bank 側に lazy provision されていない AuthCore ユーザーの扱い**
   - 「AuthCore には居るが bank には居ない」状態のユーザーは検索結果に出ない（`users` テーブルに存在しないため自然）。
   - MVP の前提として「送金前に当該ユーザーが一度でも bank ログインしている必要がある」を維持。
5. **タイミング攻撃対策（0 件 / N 件のレスポンス時間統一）**
   - 優先度低。MVP では入れない判断で良い。
6. **レート制限の閾値（30/min, 60/min）が適切か**
   - 実運用での search 頻度を見て調整。MVP は厳しめ仮値で良い。
7. **クエリ正規化**
   - 全角 / 半角、カタカナ / ひらがな の正規化を行うか。MVP では行わず、表記揺れは UX で許容する判断。
   - 将来 `unaccent` 拡張や `normalize_query` 関数を入れる余地は残す。
8. **異常検知ログのアラート閾値**
   - 短時間に同一 actor から大量検索（例: 1 分以内に 25 件以上、または 1 時間以内に 200 件以上）でアラート。
   - 実装は本タスクの範囲外（ロギングだけ仕込み、アラートは別タスクで）。

## 採用方針の変遷（履歴）

> 「試行錯誤の履歴を残す」方針（user memory `feedback_keep_trial_error_history.md`）に従い、
> 過去の検討経緯を残す。

### 2026-05-XX（初版）: 候補 1（public_id 完全一致）を推奨

- 当初は `GET /users/lookup?public_id=xxx` を推奨方針として起票。
- 理由:
  - public_id は AuthCore 側で一意保証されているため、結果は **0 or 1 件** に収束し UX が単純。
  - クライアント側もエラーハンドリング（404 ⇒「該当ユーザーがいません」）が単純。
  - enumeration リスクが低い（public_id を知っている人だけ解決可能）。
- 候補 3（表示名検索）は MVP では採用せず、将来拡張として保留する判断だった。

### 2026-05-10（現行）: 候補 3（表示名検索）に転換

- ユーザーの UX 方針確定: 「送金先選択画面で **表示名で絞り込んで** 候補から選ぶ」。
- 理由:
  - public_id を覚えていないユーザーには候補 1 が使いづらい（「友達の public_id を知らないと送れない」体験）。
  - 表示名重複は仕様上 OK で、UX 側で「アイコン + public_id 末尾4桁」を併記すれば識別可能。
  - enumeration 攻撃対策は強化（認証必須 + 厳しめレート制限 + クエリ最低 2 文字 + 個人情報非開示 + 異常検知ロギング）で吸収可能と判断。
- 候補 1 は本タスクから外す。将来必要になれば別タスクで追加可能（DTO 互換は保つ）。

### 比較表（参考）

| 候補 | エンドポイント案 | 利点 | 欠点 | 本タスクでの扱い |
|---|---|---|---|---|
| 候補 1 | `GET /users/lookup?public_id=xxx`（bank） | bank 完結。AuthCore の public_id をキーにすることで一意性も担保 | public_id を覚えていないと使えない / UX が硬い | **不採用**（履歴残し） |
| 候補 2 | AuthCore に `GET /v1/user/lookup?public_id=xxx` を追加 | AuthCore の責務（識別子）に沿う | 2 段階呼び出し / AuthCore リポジトリ側にも変更が必要 | **不採用** |
| 候補 3 | `GET /users/search?q=xxx`（bank、表示名検索） | UX 上「表示名だけで送れる」が成立。クライアントが public_id を覚えなくて良い | 表示名は重複しうる / なりすまし誘導リスク → 対策必要 | **採用（推奨）** |

## 関連タスク

- クライアント側: [`docs/tasks/client-bank-22-money-transfer.md`](./client-bank-22-money-transfer.md)
- 関連バックエンドタスク: [`docs/tasks/server-bank-23-transfer-mfa-verify-flow.md`](./server-bank-23-transfer-mfa-verify-flow.md)
  （送金時 `MFA_REQUIRED` の解消経路の仕様確認。クライアント計画書 Open Question 4 に対応）
