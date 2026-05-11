# server-bank-24: `/ledger/transfer` を external_user_id (ULID) 受け入れに揃える

## 概要

`POST /ledger/transfer` の `to_user_id` を **AuthCore ULID (`external_user_id`) 受け取り**
に切り替え、`/ledger/mint` の `resolve_recipient!` + `UserProvisioner.call(external_user_id:)`
パターンに揃える。同時に `from_user_id` は body から落とし、サーバが `current_user`
を送金元として強制する。これにより `GET /users/search` (ULID) → `POST /ledger/transfer`
の動線が develop で end-to-end に繋がる。

## 背景・目的

### 現状の不一致

PR #101 (`users-search-authcore-delegation`) で `GET /users/search` のレスポンス `id` が
**bank PK (bigint) → AuthCore ULID (string, 26 文字 = `external_user_id`)** に切り替わったが、
`POST /ledger/transfer` は依然 `User.find(transfer_params[:to_user_id])` で bank PK を
期待する実装のまま残っている。

| エンドポイント | `*_user_id` の意味 | 解決ロジック | ファイル |
|---|---|---|---|
| `POST /ledger/mint` | external_user_id (ULID) | `resolve_recipient!` + `UserProvisioner.call(external_user_id:)` | `app/controllers/ledger_controller.rb` |
| `POST /ledger/transfer` | **bank PK (bigint)** | `User.find(...)` | `app/controllers/ledger_controller.rb` |
| `GET /users/search` レスポンス `id` | **AuthCore ULID (= external_user_id)** | AuthCore 委譲 | `app/services/authcore/user_search_client.rb` |

クライアントは search で得た ULID をそのまま `to_user_id` に詰めて送るため、
現行 `LedgerController#transfer` では `User.find(ULID_string)` → 数値変換失敗 /
`ActiveRecord::RecordNotFound` になる。MVP の送金フロー（client-bank-22）が
end-to-end で動かない直接原因。

### 採用方針

`/ledger/mint` が既に `external_user_id` 入力を `UserProvisioner.call(external_user_id:)` で
ULID → `User` に lazy 解決する経路を持っているため、これを transfer にも適用する。
クライアント側は search レスポンスの ULID をそのまま `to_user_id` に渡せばよく、
中間で bank PK を意識する必要がなくなる。

cross-service identity の長期方針（`bank.users.public_id` はキャッシュ扱い、識別子は
AuthCore ULID に統一）とも整合する。`bank.users.id` (bigint) は内部リレーション専用に
閉じていく。

## スコープ

### 含む

- `LedgerController#transfer` の `User.find(to_user_id)` / `User.find(from_user_id)` を
  ULID resolve 経路に切替（`resolve_recipient!` を generic 化して mint と共通化）
- `from_user_id` を body から削除し、`current_user` を送金元として強制
- `transfer_params` (strong parameters) から `from_user_id` を除去
- ULID 形式バリデーション（`User::ULID_REGEX` 既存定数を利用、不正時 400 `VALIDATION_FAILED`）
- bank に未存在の `to_user_id` ULID は `UserProvisioner` で lazy 作成して送金成立
- `UsersController#serialize_user` に `sub: user.external_user_id` を 1 行追加
  （client の `SessionStore` 切替が同時にアンブロックされる）
- `spec/requests/ledger_transfer_spec.rb` の全面書き換え:
  - `from_user_id: from_user.id` を body から削除し、`from_user` は JWT sub と一致させる
  - `to_user_id` は `to_user.external_user_id` (ULID) で送る
  - bank 未存在 ULID を `to_user_id` に渡したケースを新規追加（lazy provision で新規 User + Account 作成）
  - ULID 形式違反 (`to_user_id`) のケースを新規追加
- README の主要 API 表に「`to_user_id` は external_user_id (ULID)、送金元は JWT current_user」と追記

### 含まない

- `/ledger/mint` 側の挙動変更（既に ULID 受け入れ済み）
- `GET /users/search` の追加変更（PR #101 完了済み）
- `bank.users.public_id` カラムの削除（cross-service identity 長期方針別タスク）
- 送金時 MFA step-up (`server-bank-23`) の配線
- `Ledger::Transfer.amount` の上限導入（別タスクで判断）
- AuthCore 側の変更（不要）

## 決定事項 / 採用方針

ドラフトで残っていた Open Question は以下のとおり確定済み。

1. **`from_user_id` を body から落として JWT `current_user` に倒すか**
   - **決定: 候補 A 採用**。body から `from_user_id` を削除し、サーバが必ず
     `current_user` を送金元に使う。strong parameters からも消す。spec も
     `from_user_id` を渡さない形に書き換える。
   - 理由: なりすまし送金の攻撃面を閉じ、API を綺麗に保つ。代理送金は将来的に
     別 endpoint で扱う。

2. **bank 未存在の `to_user_id` ULID の扱い**
   - **決定: 候補 A 採用**。`UserProvisioner.call(external_user_id:)` で lazy 作成
     して送金成立（mint と同じ挙動）。
   - 理由: mint と挙動を揃え、cross-service identity 方針（AuthCore = directory）
     と整合する。

3. **`UserResponse.sub` を本タスクで非 null 返却にするか**
   - **決定: 採用**。`UsersController#serialize_user` に `sub: user.external_user_id`
     を 1 行追加する。client `SessionStore` 切替が同時にアンブロックされ追従コストが下がる。

4. **`Ledger::Transfer.amount` の上限導入**
   - **本タスクのスコープ外**。別タスクで判断する。

5. **既存テストアカウントの後方互換**
   - staging 環境の既存テストアカウントは ULID ベースに切り替わる。本タスク完了時に
     QA 担当者へ「`curl` で送金スクリプトを叩く際は `to_user_id` を ULID
     (`external_user_id`) に変更すること、`from_user_id` は不要になること」を伝達する。
     完了条件「手動 staging 確認」に含める。

### エラーコード / HTTP status の整合

| ケース | HTTP | code |
|---|---|---|
| `to_user_id` 欠落 / ULID 形式違反 / 自己送金 / `amount` <= 0 / Idempotency-Key 欠落 | **400** | `VALIDATION_FAILED` |
| 残高不足 | 422 | `INSUFFICIENT_BALANCE` |
| 認証 / introspection 系 | 401 / 503 | `UNAUTHENTICATED` / `TOKEN_INACTIVE` / `AUTHCORE_UNAVAILABLE` |

`ValidationFailedError` は本リポジトリでは `http_status: :bad_request` (400) を返す実装
(`app/errors/validation_failed_error.rb`)。`InsufficientBalanceError` は `BankError`
のデフォルト 422 を踏襲する。

## スキーマ変更

なし（`db/Schemafile` への変更は不要）。

## API 仕様（変更点）

### `POST /ledger/transfer`

**変更前 (develop)**:

```json
{
  "ledger": {
    "from_user_id": 7,
    "to_user_id": 12,
    "amount": 100,
    "memo": "thanks",
    "metadata": {}
  }
}
```

**変更後 (本タスク)**:

```json
{
  "ledger": {
    "to_user_id": "01HX4T8K7N9P2QABC0DEF1Y0K2",
    "amount": 100,
    "memo": "thanks",
    "metadata": {}
  }
}
```

- `from_user_id` は body から廃止。送金元は JWT (`current_user`) で確定する。
- `to_user_id` は ULID 26 文字（`User::ULID_REGEX`）の `external_user_id`。
- bank に未存在の `to_user_id` ULID は `UserProvisioner` で lazy 作成される（mint と同じ）。

### バリデーション / エラー対応表

| ケース | HTTP | code | 備考 |
|---|---|---|---|
| `to_user_id` 欠落 | 400 | `VALIDATION_FAILED` | "to_user_id is required" |
| `to_user_id` が ULID 形式違反 | 400 | `VALIDATION_FAILED` | "to_user_id must be a ULID (external_user_id)" |
| `current_user` と `to_user_id` が同一 ULID | 400 | `VALIDATION_FAILED` | "cannot transfer to self"（既存 `Ledger::Transfer` の `@from_user.id == @to_user.id` チェックを ULID 経由でも維持） |
| `to_user_id` の ULID が bank に未存在 | 200 | （正常） | `UserProvisioner.call(external_user_id:)` で lazy 作成 |
| `amount` <= 0 | 400 | `VALIDATION_FAILED` | 既存維持 |
| 残高不足 | 422 | `INSUFFICIENT_BALANCE` | 既存維持 |
| 認証 / introspection 系 | 401 | `UNAUTHENTICATED` / `TOKEN_INACTIVE` | 既存維持 |
| Idempotency-Key 欠落 | 400 | `VALIDATION_FAILED` | 既存維持 |

## 影響範囲

- **変更対象**:
  - `app/controllers/ledger_controller.rb` — `transfer` アクション書き換え、
    `resolve_recipient!` を `resolve_party_by_external_user_id!` (仮) として generic 化、
    `transfer_params` から `from_user_id` を削除
  - `app/controllers/users_controller.rb` — `serialize_user` に `sub` を追加
  - `spec/requests/ledger_transfer_spec.rb` — 全面書き換え
  - `spec/requests/users_spec.rb` — `serialize_user` の expectation に `sub` 追加
  - `README.md` — 主要 API 表の `/ledger/transfer` 行更新
  - `docs/tasks/INDEX.md` — 本タスク追記
- **破壊的変更**: あり
  - `POST /ledger/transfer` の payload セマンティクスが変わる（bank PK → ULID、`from_user_id` 廃止）
  - 既存クライアントは即時 400 / 404 系で落ちる
  - client 側追従タスク (`fuju-bank-app` の `transfer-external-user-id-alignment.md`)
    と同じデプロイで揃える
- **外部層（マイニング / SNS）への影響**: なし
  - 代理 mint (`/ledger/mint`) は別エンドポイントで挙動不変

## 実装ステップ

1. **コントローラ書き換え** (`app/controllers/ledger_controller.rb`)
   - 既存の `resolve_recipient!(external_user_id)` を generic 化（例:
     `resolve_party_by_external_user_id!(external_user_id, field:)`）して、エラー
     メッセージに渡されたフィールド名（`user_id` / `to_user_id`）を埋め込めるようにする。
   - mint からも新シグネチャを呼ぶよう更新（`resolve_party_by_external_user_id!(mint_params[:user_id], field: :user_id)`）。
   - `transfer` を以下に書き換え:
     ```ruby
     def transfer
       to_user = resolve_party_by_external_user_id!(transfer_params[:to_user_id], field: :to_user_id)

       tx = Ledger::Transfer.call(
         from_user: current_user,
         to_user: to_user,
         amount: transfer_params[:amount].to_i,
         idempotency_key: idempotency_key!,
         memo: transfer_params[:memo],
         metadata: transfer_params[:metadata].to_h,
         occurred_at: parse_occurred_at(transfer_params[:occurred_at]),
       )

       render(json: serialize_transaction(tx), status: :ok)
     end
     ```
   - `transfer_params` から `:from_user_id` を削除し、`params.expect(ledger: [:to_user_id, :amount, :memo, :occurred_at, { metadata: {} }])` に整える。

2. **自己送金禁止チェックの動作確認** (`app/services/ledger/transfer.rb`)
   - 既存の `@from_user.id == @to_user.id` (bank PK 比較) はそのまま。
     `current_user` と `UserProvisioner.call` の戻り値は同じ `external_user_id` を持つ
     User なので、解決後の `users.id` が一致して弾ける。spec で動作担保する。

3. **`UserResponse.sub` の同梱** (`app/controllers/users_controller.rb#serialize_user`)
   - `sub: user.external_user_id` を 1 行追加する（既存フィールドは破壊しない）。

4. **request spec 書き換え** (`spec/requests/ledger_transfer_spec.rb`)
   - 既定の JWT は `auth_headers` ヘルパで `sub: "01HYZ0000000000000000000AA"` を発行
     するため、`from_user` を「JWT sub と同じ ULID を持つ User」として用意するか、
     `current_user` の lazy provision に任せて `from_user` は明示生成しない方針に変更する。
     方針案: `let!(:from_user) { create(:user, external_user_id: "01HYZ0000000000000000000AA") }`
     とし、残高は従来通り `from_user.account.update!(balance_fuju: 500)` でセットする。
   - 全ての `post_transfer` 呼び出しから `from_user_id:` を削除し、`to_user_id:`
     は `to_user.external_user_id` を渡す形に書き換える。
   - 既存ケースの維持:
     - 正常系（記帳・残高変動・レスポンス body・metadata・occurred_at・memo nil）
     - 冪等性（Idempotency-Key 同一で 2 回叩いて 1 件のみ）
     - 残高不足 → 422 `INSUFFICIENT_BALANCE`
     - 自己送金禁止 → 400 `VALIDATION_FAILED`（`to_user_id` に `from_user.external_user_id` を渡す）
     - `amount=0` / `amount=-10` → 400 `VALIDATION_FAILED`
     - Idempotency-Key 未指定 → 400 `VALIDATION_FAILED`
     - 認証ポリシー一式（既存維持）
   - 新規ケース:
     - `to_user_id` 欠落で 400 `VALIDATION_FAILED`
     - `to_user_id` が ULID 形式違反（bank PK の数値文字列 `"999999"` や乱文字列）で 400 `VALIDATION_FAILED`
     - bank に未登録の ULID を `to_user_id` に渡すと `UserProvisioner` で
       新規 User + Account(kind: "user", balance_fuju: 0) が作られ、送金が成立する
   - 削除するケース:
     - `from_user_id`/`to_user_id` が bank PK で存在しない → 404（API 仕様変更により消滅）

5. **`spec/requests/users_spec.rb` の expectation 追加**
   - `serialize_user` のキー一覧に `sub` を追加（`/users/me` / `show` レスポンスを
     検証している箇所）。

6. **README 更新**
   - 主要 API 表の `/ledger/transfer` 行を「`to_user_id` は external_user_id (ULID)、
     送金元は JWT current_user で確定」と追記する。

7. **`docs/tasks/INDEX.md` への追記**
   - 「個別タスク」表に本タスクを 1 行追加する。
   - ステータスは INDEX 側で管理（本ファイルには書かない）。

8. **手動 staging 確認**
   - ULID ベースで A → B 送金が `curl` で成功すること。
   - 旧仕様（bank PK の `from_user_id` / `to_user_id`）で叩くと 400 で落ちることを
     確認し、QA 担当者に送金スクリプトの更新を伝達する。

## テスト要件

### RSpec ファイル

- `spec/requests/ledger_transfer_spec.rb`（全面書き換え）
- `spec/requests/users_spec.rb`（`serialize_user` の `sub` 追加分のみ）

### 確認すべき正常系

- `to_user_id` に bank 既存 User の `external_user_id` を渡すと記帳され、from -N / to +N
- `to_user_id` に bank 未登録の ULID を渡すと新規 User + Account が作成され、送金成立
- 同一 `Idempotency-Key` で 2 回 POST しても 1 件のみ作成、2 回目も 200 で既存を返す
- `metadata` がネスト Hash でも JSONB に保存される
- `occurred_at` 未指定で `Time.current` が保存される
- `memo` 未指定で nil 保存される
- `/users/me` レスポンスに `sub: <external_user_id>` が非 null で含まれる

### 異常系 / 境界値

- `to_user_id` 欠落 → 400 `VALIDATION_FAILED`
- `to_user_id` ULID 形式違反（数値文字列 / 乱文字列）→ 400 `VALIDATION_FAILED`
- `to_user_id` が `current_user.external_user_id` と同一 → 400 `VALIDATION_FAILED`
  ("cannot transfer to self")
- `amount=0` / `amount=-10` → 400 `VALIDATION_FAILED`
- 残高不足 → 422 `INSUFFICIENT_BALANCE`（記帳されず残高不変）
- Idempotency-Key 未指定 → 400 `VALIDATION_FAILED`
- 認証ポリシー（既存 maintained）:
  - introspection inactive → 401 `TOKEN_INACTIVE`
  - introspection 5xx → 503 `AUTHCORE_UNAVAILABLE`
  - introspection の sub がローカル JWT の sub と食い違う → 401 `UNAUTHENTICATED`
  - 無効 JWT → 401 `UNAUTHENTICATED`（introspection は呼ばれない）

## 技術的な補足

### `current_user` と JWT sub の整合

`spec/support/auth_helpers.rb#auth_headers` のデフォルト `sub` は
`"01HYZ0000000000000000000AA"`。spec 書き換え時は `from_user` の `external_user_id`
を同値にしないと、`current_user` の lazy provision が別ユーザを作って `from_user`
の残高が反映されない。

代替案として `from_user` を `let!` で明示生成せず `current_user` の lazy provision に
任せ、残高は `let!(:current_user_record) { create(:user, external_user_id: "01HYZ0000000000000000000AA").tap { |u| u.account.update!(balance_fuju: 500) } }` のような形にしても良い。
実装時に簡潔な方を選ぶ。

### `resolve_recipient!` の generic 化

mint と transfer で同じ「ULID 形式チェック + `UserProvisioner` lazy 解決」をするため、
mint 側の `resolve_recipient!(external_user_id)` を `resolve_party_by_external_user_id!(external_user_id, field:)`
にリネームして両者から呼ぶ形に統合する（命名は実装時に細かく調整可）。ハッカソン文脈
なので過剰な抽象化は避け、エラーメッセージのフィールド名差し替えだけ generic に倒す。

### `Ledger::Transfer` の自己送金禁止チェック

`@from_user.id == @to_user.id` は bank PK 比較のまま維持する。`current_user` と
`UserProvisioner.call(external_user_id: to_ulid)` は同じ `external_user_id` であれば
同じ User レコードを返すので、bank PK 比較でも自己送金は弾ける。spec で「ULID 経路でも
自己送金が 400 になる」ことを担保する。

### 関連タスク

- 追従先（クライアント）: `fuju-bank-app/docs/tasks/transfer-external-user-id-alignment.md`
- 関連（前提）: `docs/tasks/users-search-cross-service-identity.md`（cross-service identity 長期方針）
- 関連（同時期）: `docs/tasks/server-bank-23-transfer-mfa-verify-flow.md`（MFA step-up は別動線）
