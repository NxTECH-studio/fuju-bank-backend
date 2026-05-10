# users-search-by-public-id

## 概要

`GET /users/search` の検索キーを `users.name` の ILIKE 部分一致から
`users.public_id` の **大文字小文字無視・前方一致** に切り替える。
AuthCore の世界観（`public_id` ハンドルが一意の対人識別子）に揃え、
staging で空配列しか返らない問題（`name` ベース検索の不発）を解消する。

## 背景・現状の問題

### staging で空配列しか返らない

```
GET https://api.fujupay.app/users/search?q=tokyo  →  {"users":[]}
```

クライアント側からの動作確認で「誰も表示されない」と報告されている。

### 根本原因: 検索キー (`users.name`) がほぼ未充填

- bank 側 `users.name` は lazy provisioning 時に NULL で作られ、
  HUD など別経路の PATCH でしか設定されない（`db/Schemafile:14` のコメント参照）。
- AuthCore 側 `users` テーブルにはそもそも `name` / `display_name` カラムが存在しない
  （`infrastructure/persistence/migrations/0001_init.up.sql` 確認済み。
  `display_name` は `social_accounts` の per-provider カラムにのみ存在）。
- したがって AuthCore からの引き継ぎ経路では `name` を埋められず、
  実運用では `name` カラムは大半が NULL のまま放置されている。

### 採用方針: AuthCore のハンドル世界観に揃える

AuthCore は `public_id`（英数 + `_`/`-`、3〜16 文字、`public_id_lower` で
正規化 UNIQUE）をユーザーの一意ハンドルとして公開している。
bank 側もこのハンドルでの検索に切り替えれば、
「クライアントが覚えやすい / なりすまし誘導リスクが低い / AuthCore と用語が揃う」
の 3 点で UX・実装ともに整合する。

エンジニア決定: **検索キーを `users.public_id` に切り替える**。

## 方針

### 1. 検索クエリ

```ruby
# 推奨: SQL 側で LOWER() 吸収（Schemafile に手を入れない最小変更）
users = User
  .where("LOWER(public_id) LIKE LOWER(?)", "#{ActiveRecord::Base.sanitize_sql_like(q)}%")
  .where.not(id: current_user.id)
  .order(:id)
  .limit(limit)
```

- **大文字小文字無視**: AuthCore の `public_id_lower` ポリシーに合わせ、
  両辺を `LOWER()` で揃える（`ILIKE` は `%` ワイルドカードが必要なので使わない）。
- **前方一致** (`"#{q}%"`): 部分一致ではなく **前方一致** を採用する。
  - 理由: `public_id` はハンドルなので前方一致で十分実用に足り、
    部分一致だと「`a` で検索 → 全 `a*` ハンドル列挙可能」と enumeration リスクが高い。
    introspection で active=true を要求する既存の抑止と合わせ、
    前方一致 + 最低 2 文字でリスクを許容範囲に収める。
- **`sanitize_sql_like`**: `%` / `_` のリテラル化は引き続き必須。
- **既存制約は維持**: 最低 2 文字 / 上限 64 文字 / `limit` デフォルト 10・上限 20 /
  自分自身除外 / introspection (`active=true`) 要求。

### 2. データの供給源

- bank `users.public_id` は既に `POST /users/me`（`UsersController#upsert_me`
  → `UserProvisioner.call`）の `public_id:` パラメータで保存される設計
  （`app/services/user_provisioner.rb:5,31`）。クライアントが AuthCore の登録レスポンス /
  プロフィール取得経路で取得した `public_id` をこの口に渡せばヒット可能になる。
- **bank 側だけで完結させる経路は今回スコープ外** とする:
  - AuthCore JWT の claims には `public_id` が含まれていない
    （`fuju-system-authentication/pkg/crypto/jwt.go:82-88` の `Claims`
    構造体は `Type / TokenFamily / Scope / MFAVerified` のみ。`sub` は `users.id`）。
    JWT verifier から拾うことはできない。
  - AuthCore introspection レスポンスは `username` フィールドに `PublicID` を入れている
    （`fuju-system-authentication/usecase/introspect_uc/service.go:109`、
    bank の `Authcore::IntrospectionResult#username` で取得可能）が、
    現状 lazy provision 経路（`JwtAuthenticatable#current_user`）は introspect を呼ばないため、
    introspect 経由補完を導入すると参照系全体に introspect の DB / HTTP コストが乗る。
    ハッカソン優先度では割に合わず、後続タスク扱いとする（後述）。

### 3. enumeration リスクの扱い

- 前方一致 + 最低 2 文字 + introspection 要求 + limit 20 で許容する。
- ハッカソン文脈で本番品質より動くこと優先という前提に基づく判断
  （rate-limit / 監査ログ / pg_trgm 化などの強化は
  `server-bank-22-recipient-resolution-api.md` の後続タスク欄に既に列挙済み）。

### 4. レスポンス（表示名 → ID 中心へ）

- `serialize_search_hit` から **`name` フィールドを除去** し、`{ id, public_id, icon_url: nil }` に変更する。
  - 検索キーが `public_id` に切り替わったことに合わせ、UI も「表示名 → ID」を主軸に倒すという
    エンジニア決定に追従する。
  - bank の `users.name` は AuthCore に対応カラムが無く、実運用でも大半 NULL のまま意味のある
    表示が出ない。返さない方がクライアント側で「null フォールバックでハンドルを出す」分岐を
    書かずに済み、表示の一貫性も担保できる。
- `id`（bank 内部 user ID、送金時の宛先指定に必要）は維持。`public_id` は表示用 + 完全一致確認用。
- `serialize_user`（`/users/me` 等の自分参照系）の `name` フィールドはクライアントの登録 UI 等で
  使われている可能性があるため **本タスクでは触らない**。検索ヒットだけ ID 中心に切り替える。
- 表示名相当が将来必要になったら、AuthCore introspection の `username` (= `PublicID`) や
  `social_accounts.display_name` 経由で別途設計する（後続タスク欄に記載）。

### 5. スキーマ

- **Ridgepole 変更なし**。`users.public_id` は既存カラムをそのまま使う。
- `public_id_lower` カラム追加 / 関数 index (`CREATE INDEX ... ON users (LOWER(public_id))`)
  追加は **見送り**（理由）:
  - ハッカソン規模では `LOWER(public_id) LIKE 'foo%'` をフルスキャンで捌いても十分。
  - 既存の `index_users_on_public_id_unique_when_present` (UNIQUE 部分 index) は
    検索 SARG-able ではないがルックアップ用途で残す価値がある。
  - 性能が問題化したら本タスクのスコープ外で関数 index を追加すれば良い。

## 影響範囲

- **変更対象**:
  - `app/controllers/users_controller.rb` — `search` の WHERE 句のみ書き換え。
    既存 validation / serialization / introspection / 自分除外は維持。
  - `spec/requests/users_search_spec.rb` — テストケース全面書き換え
    （「name で検索する」前提を「public_id で検索する」前提に変更）。
  - `README.md` — API 一覧の `/users/search` 行の説明文を「ハンドル前方一致」に更新。
  - `docs/tasks/INDEX.md` — 本タスクを追記。
- **破壊的変更**: あり（`GET /users/search?q=xxx` の `q` の意味が `name` → `public_id` に変わる）。
  - クライアントは現状 `name` ベースで叩いていたつもりだが、staging で 0 件しか返っていないので
    実害はない。クライアント側もハンドル入力 UI に揃えるべきだが、レスポンス JSON の
    キー構成は変わらないので互換維持される。
- **外部層（マイニング / SNS）への影響**: なし。

## スキーマ変更

なし。`db/Schemafile` は触らない。

## 実装ステップ

1. **`app/controllers/users_controller.rb` の `search` を書き換え**
   - `User.where("name ILIKE ?", "%#{...}%")` を
     `User.where("LOWER(public_id) LIKE LOWER(?)", "#{...}%")` に置き換え
     （`sanitize_sql_like` は維持、ワイルドカードは末尾のみ）。
   - クラス上部の説明コメント (`L39-41`) を「`public_id` 前方一致（大文字小文字無視）」に更新。
   - **`serialize_search_hit` から `name` キーを削除** し、`{ id, public_id, icon_url: nil }` に変更
     （UI を「表示名 → ID」中心に倒す方針への追従。`serialize_user` 側は触らない）。
   - 定数 (`SEARCH_DEFAULT_LIMIT` 等) と `validate_search_query!` / `parse_search_limit` は
     そのまま流用。

2. **`spec/requests/users_search_spec.rb` を書き換え**
   - `let!(:alice1) { create(:user, name: "アリス", public_id: "alice") }` 等の固定値はそのまま使えるが、
     `get("/users/search", params: { q: "アリス" })` を `q: "ali"` のような **public_id 前方一致** に変更。
   - **正常系**:
     - `q: "ali"` で `alice` / `alice2024` がヒット（前方一致）。
     - `q: "ALI"` でも同じ結果（大文字小文字無視）。
     - `q: "lic"` ではヒットしない（前方一致なので中間一致は除外）。
     - 0 件ケースは `q: "zzz"` 等に変更。
     - 自分除外は `q: caller_user.public_id` で確認。
   - **limit / SQL ワイルドカードエスケープ / バリデーション / 認証** ケースは
     `name` を `public_id` に置き換えるだけで構造は流用。
     - `limit` 系の `create_list(:user, 25, name: "サンプル太郎")` は public_id が未指定だと NULL で
       検索ヒットしない。`create_list(:user, 25)` でループしながら `public_id: "sample#{i}"` を
       付与するか、ファクトリ側で sequence を入れて `q: "sample"` で 25 件作る形に変更する。
     - `SQL ワイルドカードエスケープ` の `100%off` は public_id にできない（`%` は format で弾かれる）ので、
       `_` を含む public_id（`u_plain` / `u_test`）で `q: "u_"` を投げて全マッチにならないことを検証する形に変える。
   - 既存の `RSpec/PreferLetBang` cop に従い `let!` を維持。

3. **`spec/factories/users.rb` の確認**（必要に応じて修正）
   - `public_id` を sequence で埋める factory trait があれば流用、無ければ
     `sequence(:public_id) { |n| "user#{n}" }` を追加して spec 全体で重複しないようにする。
     既存 spec が `public_id: nil` 前提で書かれている場合は明示 nil 指定に書き換える必要があるか
     念のため `Grep` で確認する。

4. **`README.md` の API 一覧を更新**
   - L65 の説明を
     「送金先検索（**`public_id` 前方一致 / 大文字小文字無視**、最大 20 件、自分除外）」に変更。

5. **`docs/tasks/INDEX.md` に本タスクを追記**
   - 「個別タスク」表に行追加。
   - `server-bank-22-recipient-resolution-api.md` の行のステータス注記
     「（pg_trgm / AuditLog / rack-attack / icon_url / backfill は別タスク）」は維持。

6. **テスト実行**
   - `make rspec ARGS=spec/requests/users_search_spec.rb` で全パス確認。
   - `make rubocop` で lint パス確認（`Style/HashSyntax: never` / 行 160 文字 / ダブルクォート）。

## 動作確認手順

### local

```bash
# 1) 適当な public_id でユーザーを 2 件作る
curl -X POST http://localhost:3000/users/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN_USER_A}" \
  -H "Content-Type: application/json" \
  -d '{"public_id":"alice"}'

curl -X POST http://localhost:3000/users/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN_USER_B}" \
  -H "Content-Type: application/json" \
  -d '{"public_id":"alice2024"}'

# 2) 検索（caller は別ユーザーで叩く）
curl "http://localhost:3000/users/search?q=ali" \
  -H "Authorization: Bearer ${ACCESS_TOKEN_USER_C}"
# → {"users":[{"id":..,"public_id":"alice","icon_url":null},
#             {"id":..,"public_id":"alice2024","icon_url":null}]}

# 3) 大文字小文字無視確認
curl "http://localhost:3000/users/search?q=ALI" \
  -H "Authorization: Bearer ${ACCESS_TOKEN_USER_C}"
# → 同じ結果

# 4) 中間一致は弾かれる（前方一致）
curl "http://localhost:3000/users/search?q=lic" \
  -H "Authorization: Bearer ${ACCESS_TOKEN_USER_C}"
# → {"users":[]}
```

### staging

ローカルで通った後、`develop` PR → マージ → staging デプロイ後に
`api.fujupay.app` で同様の curl を実行して確認する。
ただし staging の DB に `public_id` 入りのユーザーが居ない場合は事前に
`POST /users/me` で 1〜2 件 backfill が必要（クライアント側の対応とセットでないと
動作確認できない可能性がある旨をエンジニアに伝える）。

## テスト要件

- **正常系**:
  - 前方一致でヒット (`q: "ali"` → `alice`, `alice2024`)
  - 大文字小文字無視 (`q: "ALI"` で同上)
  - 中間一致では拾わない (`q: "lice"` → 0 件)
  - `public_id` が NULL のレコードは絶対にヒットしない
  - 自分自身は除外される（`q: caller.public_id` でも自分は出ない）
  - レスポンスキー構成は `{ id, public_id, icon_url }` の 3 キー（`name` は含まれない）
  - bank `users.name` の値（NULL 含む）はレスポンスに影響しない（返さないため）
- **異常系 / 境界値**:
  - `q` 1 文字 → 400、65 文字 → 400、空文字 / 空白のみ → 400
  - `limit` 0 / 21 / 非数値 → 400
  - SQL ワイルドカード `_` のリテラル化（`u_x` の存在下で `q: "u_"` が全マッチにならない）
- **認証**:
  - Authorization なし → 401 UNAUTHENTICATED
  - introspection inactive → 401 TOKEN_INACTIVE
  - mfa_verified=false でも 200（既存挙動維持）
- **テストファイル**: `spec/requests/users_search_spec.rb`（既存ファイルを書き換え）

## 技術的な補足

- **`ILIKE` ではなく `LOWER(...) LIKE LOWER(...)` を使う理由**: `ILIKE` は PostgreSQL 拡張で
  既存コードでも使っており動くが、`public_id_lower` カラムを持つ AuthCore 設計と
  対応関係を明示するため、こちらの形に揃える。
  PostgreSQL 12 以降は `LOWER()` も `ILIKE` も性能差は実質ない（どちらも index 関数化が必要）。
- **前方一致 vs 部分一致の選択**: server-bank-22 のとき部分一致を採用したのは「日本語の name で
  途中マッチを許したい」要求に基づくもの。今回は ASCII ハンドルなので前方一致で実用十分、
  かつ enumeration リスクが下がる。中間一致が欲しい要望が出たら後続タスクで切り替えれば良い。
- **既存の部分 UNIQUE index (`index_users_on_public_id_unique_when_present`)**: `public_id` の
  ルックアップ（完全一致）には使えるが、今回の `LOWER(public_id) LIKE 'foo%'` には効かない。
  ハッカソン規模ではフルスキャンで OK との判断。

## 未決事項 / 後続タスク

- **クライアント側 (`fuju-bank-app#client-bank-22`)**: 現状 `POST /users/me` の呼び出しが
  AuthCore の `public_id` を渡しているか要確認。渡していなければクライアント改修が必要
  （AuthCore のサインアップ / ログインレスポンスの `public_id` を Ktor 側で保持し、
  bank への lazy provision 時に同梱する）。これは別リポジトリのタスクとして起票すること。
- **introspection 経由の lazy 補完**: `Authcore::IntrospectionResult#username` に
  AuthCore の `PublicID` が入っているので、参照系で introspect が呼ばれる経路では
  `User.public_id` を遅延補完するルートも組める。ただし参照系全体に introspect コストが
  乗ること、責務が `JwtAuthenticatable` から滲み出ることのトレードオフがあるため、
  クライアント側が安定して `public_id` を送り始めるまで保留。
- **既存ユーザーの backfill**: 既に lazy provision されていて `public_id` が NULL のレコードは
  クライアントが次回 `POST /users/me` を叩くまで検索結果に出てこない。MVP では許容
  （クライアント起動時に `POST /users/me` を必ず叩く設計なので自然と埋まる想定）。
- **検索の中間一致 / pg_trgm**: server-bank-22 の後続タスク欄に既に列挙されている通り、
  本タスクのスコープ外。
