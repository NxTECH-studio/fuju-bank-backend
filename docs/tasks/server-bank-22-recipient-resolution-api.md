# server-bank-22: 受取人解決 API（送金先 lookup）

> 本タスクは Rails 製の **fuju-bank-backend** リポジトリ側で実施する作業の計画書。
> 計画書ファイル自体はクライアント計画書 `docs/tasks/client-bank-22-money-transfer.md` と
> 一元参照したいため、本リポジトリ（`fuju-bank-app`）の `docs/tasks/` に置く。
> 実装着手時にバックエンドリポジトリへ Notion タスクと併せて移送する想定。

## 概要

クライアント側送金フロー（`client-bank-22`）が成立するために必要な、
**「ユーザー入力（表示名 / public_id）→ bank 内部 user id」を解決する公開 API** を
fuju-bank-backend に追加する。クライアントはこの API のレスポンスで得た `id` を
`POST /ledger/transfer` の `to_user_id` に詰めて送金する。

## 背景・目的

- `client-bank-22` の最大ブロッカー: クライアントが「表示名で送金先を決める」UX を
  組もうとしても、bank 側に **public_id / 表示名から bank の `users.id`（bigint）を
  逆引きする手段がない**。
- 既存 API の状況:
  - `GET /v1/user/profile`（AuthCore）: **自分自身** の AuthCore プロフィールしか取れない。
    `public_id` は AuthCore のスキーマ。
  - `GET /users/me`（bank）: **自分自身** の bank プロフィール（`balance_fuju` 等）。
  - `GET /users/:id`（bank）: bank の **内部主キー（bigint）を既に知っている前提** の API。
    クライアントは他人の bank id を知る経路がない。
  - 表示名 (`users.name`) は public_id のような一意制約がなく、現状検索 API もない。
- そのため、**任意の他ユーザーの bank id を解決する公開 API** を追加する必要がある。
- `POST /ledger/transfer` 自体は既に存在し、送信元・宛先の残高更新は 1 トランザクションで
  ledger_transactions INSERT + users.balance_fuju UPDATE が走る前提なので、本タスクの
  スコープは **lookup API の新設のみ**。送金本体は触らない。

## スコープ

### 含む

- 受取人解決エンドポイント 1 本の新設（後述「採用方針」）
- レスポンス DTO 設計（`id` / `public_id` / `name` / `icon_url` 程度）
- 認証要件・レート制限・プライバシー設計
- request spec（RSpec）と controller spec（最低限ハッピーパス + 404 + rate limit）
- README / API 仕様書（バックエンド側）への追記
- クライアント側 (`UserApi.lookup` 想定) との DTO 整合確認

### 含まない

- `POST /ledger/transfer` 本体の改修（既存の挙動を維持）
- 表示名 (`users.name`) のユニーク制約導入（後述 Open Questions で議論。本タスクでは入れない）
- フォロー / 連絡先のような新規ドメイン概念の追加
- AuthCore (`fuju-system-authentication`) 側の API 追加（候補 2 を採用しない前提）

## 候補と推奨方針

クライアント計画書 §「バックエンド前提（要ユーザー確認）」の 3 候補を整理。

| 候補 | エンドポイント案 | 利点 | 欠点 |
|---|---|---|---|
| 候補 1 | `GET /users/lookup?public_id=xxx`（bank） | bank 完結。bank の `id` を直接返せる。AuthCore 側の `public_id` をキーにすることで一意性も担保できる | bank 側で AuthCore の `public_id` を `users` 行に冗長保持する必要があるか、AuthCore に問い合わせる必要がある |
| 候補 2 | AuthCore に `GET /v1/user/lookup?public_id=xxx` を追加 → bank 側で `external_user_id → users.id` を引く | AuthCore の責務（識別子）に沿う | クライアントが 2 段階呼び出しになる / AuthCore リポジトリ側にも変更が必要で工数が増える |
| 候補 3 | `GET /users/lookup?name=xxx`（bank、表示名検索） | UX 上「表示名だけで送れる」が成立する。クライアントが public_id を覚えなくて良い | 表示名は重複しうるので 0..N 件返す UX が必要。なりすまし誘導リスク |

### 推奨: **候補 1 をベースに、候補 3 を将来拡張として残す**

- まずは **`GET /users/lookup?public_id=xxx`（候補 1）** を最小実装する。
  - public_id は AuthCore 側で一意保証されているため、結果は **0 or 1 件** に収束し、UX が単純。
  - クライアント側もエラーハンドリング（404 ⇒「該当ユーザーがいません」）が単純。
- bank 側の `users` テーブルに **`external_user_id`（= AuthCore の user id）は既に存在する** 前提
  （`POST /users/me` の lazy provision で書かれる）。`public_id` は AuthCore スキーマなので、
  bank 側に冗長カラム `users.public_id` を持たせるか、リクエストごとに AuthCore へ問い合わせるかは
  Open Questions に残す。
  - **第一候補**: bank 側 `users.public_id` カラムを追加し、`POST /users/me` 時に AuthCore から
    取得して書き込む。lookup 時は bank の DB だけで完結（高速・AuthCore に依存しない）。
  - **代替**: lookup 時に AuthCore `/v1/internal/users/by_public_id` 的な internal API を叩く
    （AuthCore 側にも追加が必要 → 候補 2 と同じ工数になり妥当性低下）。
- 候補 3（表示名検索）は MVP では **採用しない**。Open Questions に残し、必要になった時点で
  別タスクで追加する。

## API 仕様案（推奨方針 = 候補 1）

### エンドポイント

```
GET /users/lookup?public_id=:public_id
```

- 認証: AuthCore JWT（access_token Bearer）必須。bank API のデフォルト Auth プラグイン経路。
- introspection: 通常の bank API と同じく introspection で `active=true` を要求。
- レート制限: 後述。

### リクエストパラメータ

| 名前 | 型 | 必須 | 備考 |
|---|---|---|---|
| `public_id` | string | yes | AuthCore の `public_id`。3〜32 文字程度の英数字 + 一部記号（AuthCore 仕様準拠）|

将来の表示名検索（候補 3）を見越し、`public_id` と `name` の **どちらか一方** を必須とする
スキーマで設計しておく（`name` は本タスクでは未対応 = 422 を返す）。

### レスポンス

#### 200 OK

```json
{
  "id": 1234,
  "public_id": "alice",
  "name": "アリス",
  "icon_url": "https://cdn.fujupay.app/icons/abc.png"
}
```

| フィールド | 型 | nullable | 備考 |
|---|---|---|---|
| `id` | integer (bigint) | no | bank 内部 user id。`POST /ledger/transfer` の `to_user_id` に渡す |
| `public_id` | string | no | AuthCore の public_id。確認画面の補助表示に使う |
| `name` | string | yes | bank 側 `users.name`（未設定なら null）|
| `icon_url` | string (URL) | yes | AuthCore の icon_url（未設定なら null）|

> `email` / `mfa_enabled` / `balance_fuju` などはプライバシー観点で **返さない**。

#### 404 Not Found

```json
{ "error": { "code": "NOT_FOUND", "message": "ユーザーが見つかりません" } }
```

- 該当 public_id の AuthCore ユーザーがいない、または bank 側に lazy provision されていない場合。
- bank 側未 provision のケースを 404 と区別する必要があるかは Open Questions 参照。

#### 422 Unprocessable Entity

```json
{ "error": { "code": "VALIDATION_FAILED", "message": "public_id is required" } }
```

- `public_id` パラメータ欠落
- public_id のフォーマット違反（空文字、最大長超過等）

#### 401 Unauthorized

- `UNAUTHENTICATED`: access_token 欠落 / 無効
- `TOKEN_INACTIVE`: introspection で `active=false`

#### 429 Too Many Requests

```json
{ "error": { "code": "RATE_LIMIT_EXCEEDED", "message": "Too many lookup requests" } }
```

- 後述レート制限超過時。

### サーバ実装の流れ（疑似コード）

```ruby
# app/controllers/users_controller.rb
def lookup
  public_id = params.require(:public_id)
  validate_public_id_format!(public_id)  # 422 on invalid

  # 第一候補: bank の users テーブルに public_id カラムが冗長保持されている場合
  user = User.find_by(public_id: public_id)
  raise NotFoundError if user.nil?

  render json: serialize_lookup(user)
end
```

> 注: `users.public_id` カラム化は **Open Questions** で確定後に実施。
> マイグレーションは別タスクに切る or 本タスクの Phase 1 に含める。

## 認証・プライバシー

### 認証要件

- **必須**: AuthCore JWT（Bearer）+ introspection で `active=true`。
- **任意性**: 未認証ユーザーには公開しない。検索クローラ / 名前収集を防ぐため。

### レート制限

- **per user**: 60 req / minute（lookup 用途で十分）
- **per IP**: 120 req / minute
- 既存の Rack::Attack（または rack-attack）設定にエンドポイント別 throttler を追加。
- 超過時は `429 RATE_LIMIT_EXCEEDED` を返す。

### プライバシー観点

- **返さない情報**: email, balance, mfa_enabled, created_at, last_sign_in_at 等。
- **返す情報**: 送金 UI で必要最小限（id / public_id / name / icon_url）。
- **全ユーザー検索可否**: 候補 1（public_id 完全一致）の場合は「public_id を知っている人だけ
  解決可能」なため、検索リスクは最小。候補 3（表示名検索）を入れる場合は別途プライバシー設計が必要。
- **enumeration 対策**: 連続リクエストで public_id を総当たりされるのをレート制限で抑止。
  必要なら 404 と 200 のレスポンス時間を揃える（タイミング攻撃対策、優先度低）。

### 将来の拡張（フォロー / 連絡先関係）

- 現状は連絡先 / フォロー概念がないため、全 public_id を対象にする。
- 将来導入されたら、lookup 結果に `relationship: "self" | "contact" | "stranger"` を付与する余地を
  残しておく（DTO 拡張は破壊的変更なしで可能）。

## 表示名重複時の振る舞い

- 候補 1 採用 = public_id ベースのため **重複は発生しない**（AuthCore 側で一意）。
- 候補 3（将来）を実装する場合は別途仕様を決める。本タスクでは扱わない。
  - 参考案: `GET /users/lookup?name=xxx&limit=10` で 0..10 件返す。表示順は `created_at` 昇順か
    `last_sign_in_at` 降順。クライアント側で候補リスト UI を出させる。

## 影響範囲

- **追加**: `app/controllers/users_controller.rb#lookup`、`config/routes.rb` への 1 行追加
- **追加（DB）**: `users.public_id` カラム追加マイグレーション + index（unique）
  - 既存ユーザーには backfill ジョブで AuthCore から取得して埋める
- **変更**: `POST /users/me`（lazy provision）で AuthCore レスポンスから `public_id` を保存
- **変更（rack-attack）**: lookup エンドポイントの throttle ルール追加
- **変更（README）**: API 一覧表に `GET /users/lookup` を追記

## バリデーション / エラー

| ケース | HTTP | code | 備考 |
|---|---|---|---|
| `public_id` 欠落 | 422 | `VALIDATION_FAILED` | |
| `public_id` フォーマット違反（空文字 / 長すぎ / 不正文字） | 422 | `VALIDATION_FAILED` | AuthCore の public_id 仕様に合わせる |
| 該当ユーザー不在 | 404 | `NOT_FOUND` | bank 側未 provision も同じ扱い |
| access_token 欠落 / 無効 | 401 | `UNAUTHENTICATED` | |
| introspection inactive | 401 | `TOKEN_INACTIVE` | |
| レート制限超過 | 429 | `RATE_LIMIT_EXCEEDED` | |
| 自分自身を lookup | 200 | （正常） | クライアント側で「自分宛は弾く」責務とする。サーバはエコーバックで OK |

## テスト方針（RSpec）

### request spec（`spec/requests/users_lookup_spec.rb`）

```ruby
describe "GET /users/lookup" do
  context "with valid public_id" do
    it "returns the bank user id and public profile fields"
  end

  context "with non-existent public_id" do
    it "returns 404 NOT_FOUND"
  end

  context "without public_id param" do
    it "returns 422 VALIDATION_FAILED"
  end

  context "without access token" do
    it "returns 401 UNAUTHENTICATED"
  end

  context "when introspection returns inactive" do
    it "returns 401 TOKEN_INACTIVE"
  end

  context "looking up self" do
    it "returns the caller's own profile (200)"
  end

  context "rate limit" do
    it "returns 429 after the threshold" # 単体で動かしづらいので skip フラグ可
  end
end
```

### model spec / migration spec

- `users.public_id` の uniqueness 制約
- `POST /users/me` での public_id 書き込み（既存 spec の拡張）

### 副次: 既存スイートへの影響

- `POST /users/me` を変えるなら既存 request spec の更新が必要
- `POST /ledger/transfer` 関連 spec への影響はないはず（`to_user_id` は数値で受ける既存挙動のまま）

## 完了条件

1. `GET /users/lookup?public_id=xxx` が main にマージされ、staging 環境（`api.fujupay.app`）で動作
2. 既存の `POST /users/me` が AuthCore レスポンスから `public_id` を保存するように更新済み
3. 既存ユーザー全員に対して backfill 完了（`users.public_id` が NULL のレコードがゼロ）
4. RSpec が green、新規 request spec も追加済み
5. レート制限が rack-attack に組み込まれ、超過時 429 を返すことを手動確認
6. バックエンド README の API 一覧表に追記
7. クライアント `client-bank-22` 側で `UserApi.lookup(publicId)` を呼んで動作確認できる状態
   （= フロント実装の Phase 2 がアンブロックされる）

## Open Questions

1. **`users.public_id` を bank 側に冗長保持するか、毎回 AuthCore に問い合わせるか**
   - 推奨: 冗長保持（高速・AuthCore 障害耐性）。本タスクで一緒にマイグレーションを切る。
2. **bank 側に lazy provision されていない AuthCore ユーザーの扱い**
   - 「AuthCore には居るが bank には居ない」状態のユーザー宛に送金しようとした場合、
     404 を返すか、サーバ側で provision してから 200 を返すか。
   - 推奨: **404**（送金前に当該ユーザーが一度でも bank ログインしている必要がある = MVP の前提）。
3. **タイミング攻撃対策（404 と 200 のレスポンス時間統一）**
   - 優先度低。MVP では入れない判断で良いと考える。
4. **将来の表示名検索（候補 3）を本タスクのスキーマに含めておくか**
   - クエリパラメータを `?public_id=...` 固定にするか、`?public_id=...` / `?name=...` の
     どちらかを受けられる形にしておくか。後者なら将来追加が破壊的変更にならない。
   - 推奨: パラメータ名は `public_id` 固定。将来 `name` を追加する時は `?q=...&type=name`
     のような新しい検索 API として別パスで切る方が安全（プライバシー設計が変わるため）。
5. **レート制限の閾値（60/min, 120/min）が適切か**
   - 実運用での lookup 頻度を見て調整。MVP は仮値で良い。
6. **表示名のユニーク制約導入**
   - 別タスク（`server-bank-23-...` 等）として切るか、本タスクに含めるか。
   - 推奨: **別タスク**。本タスクは public_id ベースで成立するので、表示名一意化は独立した
     議論に分ける。ユニーク制約導入には既存重複データのマージ作業が発生する。

## 関連タスク

- クライアント側: [`docs/tasks/client-bank-22-money-transfer.md`](./client-bank-22-money-transfer.md)
- 関連バックエンドタスク: [`docs/tasks/server-bank-23-transfer-mfa-verify-flow.md`](./server-bank-23-transfer-mfa-verify-flow.md)
  （送金時 `MFA_REQUIRED` の解消経路の仕様確認。クライアント計画書 Open Question 4 に対応）
