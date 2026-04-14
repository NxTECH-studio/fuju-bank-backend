# ふじゅ〜 中央銀行バックエンド 初期実装プラン（学習モード）

## Context

fuju-bank-backend は Rails 8.1 API 骨組みだけで、ドメインモデルもスキーマも無い状態。`docs/api-contract.md` には 6 本のエンドポイント仕様が既に固まっている。

**ユーザーは銀行システムを作った経験がなく、まだ全体像のイメージが湧いていない**。そのため本プランは単なる実装手順ではなく、**各ステップで銀行ドメインの概念を短く解説しながら段階的に組み上げる学習ドライブな構成** にする。最終成果物は契約書に準拠した動く MVP だが、その過程で「銀行システムとはどういう部品でできているのか」を身体で理解することを同等のゴールに置く。

決定事項（ユーザー確認済み）:
- **進め方**: 解説しながら段階実装。各ステップで短い概念解説 → コード → 動作確認。
- **冪等性**: idempotency key で二重発行防止（DB unique index レベルで保証）。
- **台帳設計**: イメージが湧いていないとのことなので、**まず Phase 0 で概念プライマーを書き、そこで「単式 vs 複式」を実例で理解してもらう。本プランは複式簿記ベースで進める方針を推奨**（理由は下記）。

## なぜ複式簿記を勧めるか（プラン採用の論拠）

銀行システムの「背骨」は複式簿記 (double-entry bookkeeping) で、これを避けて通ると銀行を作った体験にならない。逆に一度自分の手で組むと、世の中のほぼ全ての会計・決済システムの構造が見えるようになるので学習コストに対するリターンが最大。

- **単式**: `ledger_entries` に `amount` を 1 行書くだけ。シンプルだが「どこから来た金か」が構造的に表現されない。残高は `SUM(amount)` で、不整合が起きても検知できない。
- **複式**: すべての取引を「借方 (debit) と貸方 (credit) のペア」で記録する。借方合計 == 貸方合計 が常に成立する（**不変条件**）。これによりバグや不正を DB レベルで検知できる。

ふじゅ〜に当てはめると、1 回の encounter は以下の 1 トランザクション:

```
(借方) 発行準備金        15 ふじゅ〜   ← 銀行が「これから配る用の原資」を減らす
(貸方) 作家口座(id=42)   15 ふじゅ〜   ← 作家の残高が 15 増える
```

合計 0 になる。台帳が壊れていないことは `SUM(debit) = SUM(credit)` を見れば一瞬で分かる。これが複式の本質。

API 契約書の外形（`POST /api/encounters` のレスポンス、`ledger_entry_id`, `amount`）は一切変えずに、内部だけこの構造で実装できる。

## Phase 0: 概念プライマー（`docs/banking-primer.md` 新規作成）

実装に入る前に、以下を 1 ファイルにまとめて短く解説する。コードを書く前にこのドキュメントをユーザーと一緒に読み合わせて「銀行の部品」の語彙を揃える。

扱うトピック（各 3〜5 行ずつ）:
1. **勘定科目 (Account)** — お金の置き場所の種類。ふじゅ〜では「発行準備金」「作家口座(per-artist)」の 2 種類だけで始める。
2. **仕訳 (Journal Entry / Transaction)** — 1 つの取引。借方と貸方のペアで成り立つ。
3. **借方・貸方 (Debit / Credit)** — どちらが増えたらどちらに書くかのルール。資産アカウント(作家口座)は借方で増える、負債アカウント(発行準備金)は貸方で増える、等。
4. **台帳 (Ledger)** — 仕訳の明細行の集合。`ledger_lines` テーブルがこれ。
5. **残高 (Balance)** — 特定アカウントの借方合計 − 貸方合計。集計は都度計算 or projection。
6. **不変条件 (Invariants)** — 1 transaction 内で `SUM(debit) = SUM(credit)`。これを DB 制約 + サービス層で守る。
7. **冪等性 (Idempotency)** — 同じ encounter を 2 度送っても発行は 1 回で済むこと。`idempotency_key` の unique index で実現。
8. **ふじゅ〜固有の翻訳** — 「encounter → 仕訳 1 本を生む」「gaze_event は生の観測ログ、ledger は会計結果」の区別。

この primer は実装中に読み返す参照点になる。README の末尾から 1 行リンクを張る。

## スキーマ設計 (`db/Schemafile`)

複式簿記 + 冪等性を備えたテーブル構成:

```ruby
create_table "artists", force: :cascade do |t|
  t.string "handle", null: false
  t.string "display_name", null: false
  t.text "public_key", null: false
  t.timestamps
  t.index ["handle"], unique: true
end

create_table "artifacts", force: :cascade do |t|
  t.bigint "artist_id", null: false
  t.string "title", null: false
  t.string "origin_type", null: false   # "physical" | "url"
  t.string "origin_ref", null: false
  t.text "description"
  t.timestamps
  t.index ["artist_id"]
end

create_table "gaze_events", force: :cascade do |t|
  t.bigint "artifact_id", null: false
  t.float "duration_seconds", null: false
  t.float "intensity_score", null: false
  t.datetime "observed_at", null: false
  t.string "client_session_id"
  t.timestamps
  t.index ["artifact_id"]
  t.index ["observed_at"]
end

# 勘定科目マスタ。シードで 1 行だけ "issuance_reserve" を入れ、作家ごとに 1 行ずつ自動作成。
create_table "accounts", force: :cascade do |t|
  t.string "kind", null: false            # "issuance_reserve" | "artist"
  t.bigint "artist_id"                    # kind=artist のときのみ
  t.string "name", null: false            # 表示名
  t.timestamps
  t.index ["kind", "artist_id"], unique: true
end

# 1 取引 = 1 transaction 行 + 複数の ledger_lines 行。
# idempotency_key により同じ encounter の二重発行を DB レベルで遮断。
create_table "transactions", force: :cascade do |t|
  t.string "idempotency_key", null: false
  t.string "kind", null: false            # "issuance"
  t.bigint "gaze_event_id"
  t.datetime "posted_at", null: false
  t.text "memo"
  t.timestamps
  t.index ["idempotency_key"], unique: true
  t.index ["gaze_event_id"]
end

create_table "ledger_lines", force: :cascade do |t|
  t.bigint "transaction_id", null: false
  t.bigint "account_id", null: false
  t.integer "debit", null: false, default: 0   # 円のような整数単位
  t.integer "credit", null: false, default: 0
  t.timestamps
  t.index ["transaction_id"]
  t.index ["account_id"]
  # DB レベルで「片側だけ 0 でない」を保証したいが、Ridgepole の CHECK 制約対応が薄いので
  # モデル validation + service で担保し、コメントで DB レベル化を TODO として残す。
end
```

**API 契約との互換性**: 契約書の `ledger_entry_id` は「ふじゅ〜を受け取った 1 件」に対応するので、`transactions.id` をそのまま `ledger_entry_id` として露出する。`amount` は該当 transaction の artist 側 ledger_line の `debit` 値。これで契約書のレスポンスは 1 文字も変わらない。

**idempotency_key の作り方**: `"encounter:#{client_session_id}:#{observed_at.iso8601}:#{artifact_id}"`。マイニング層が同じ encounter をリトライしても、2 回目は unique index 違反 → 既存 transaction を返して 201 にするか、あるいは `ActiveRecord::RecordNotUnique` を `find_by(idempotency_key:)` で拾って既存結果を返す（サービス層で実装）。

## モデル (`app/models/`)

全モデルにクラスコメント必須。

- **`Artist`** — `has_many :artifacts`, `has_one :account`（kind=artist）。`#balance` は `account.balance` に委譲。
- **`Artifact`** — `belongs_to :artist`, `has_many :gaze_events`。
- **`GazeEvent`** — `belongs_to :artifact`。生の観測ログ。
- **`Account`** — `belongs_to :artist, optional: true`, `has_many :ledger_lines`。`#balance` で `ledger_lines.sum("debit - credit")`（artist 口座は資産扱いなので借方残）。
- **`Transaction`** — `has_many :ledger_lines`。validation: `lines.sum(:debit) == lines.sum(:credit)` かつ `lines.size >= 2`。
- **`LedgerLine`** — `belongs_to :transaction, :account`。validation: `debit >= 0`, `credit >= 0`, `(debit == 0) ^ (credit == 0)`（片側だけ）。

`Transaction` モデル名は `ActiveRecord::Base.transaction` と紛らわしいので、**クラス名は `JournalEntry` に改名する**（銀行用語でも journal entry の方が正しい）。テーブル名は `journal_entries` とする。上のスキーマもそれに合わせて差し替え。

## ドメインロジック (`app/services/`)

### `Services::IssuancePolicy`
`DURATION_THRESHOLD = 3.0`, `INTENSITY_THRESHOLD = 0.3`, `AMOUNT_COEFFICIENT = 10`（暫定）。
- `.eligible?(...)` / `.calculate_amount(...)`

### `Services::EncounterProcessor`
責務: encounter リクエストを受け、gaze_event を必ず作り、閾値クリアなら journal_entry + 2 本の ledger_lines を 1 トランザクションで作成し、ArtistChannel に broadcast。

擬似コード:
```ruby
ActiveRecord::Base.transaction do
  gaze = GazeEvent.create!(...)
  return Result.new(status: :below_threshold, gaze_event: gaze) unless IssuancePolicy.eligible?(...)

  key = "encounter:#{client_session_id}:#{observed_at.iso8601}:#{artifact_id}"
  entry = JournalEntry.find_by(idempotency_key: key)
  return Result.new(status: :issued, gaze_event: gaze, journal_entry: entry) if entry

  amount = IssuancePolicy.calculate_amount(...)
  entry = JournalEntry.create!(idempotency_key: key, kind: "issuance", gaze_event: gaze, posted_at: Time.current)
  entry.ledger_lines.create!(account: artist_account, debit: amount, credit: 0)
  entry.ledger_lines.create!(account: reserve_account, debit: 0, credit: amount)
  Result.new(status: :issued, gaze_event: gaze, journal_entry: entry)
end.tap { |result| ArtistChannel.broadcast_to(artist, payload_for(result)) if result.status == :issued }
```

この 1 メソッドを読めば「銀行内部で何が起きるか」が完全に追える状態を目指す。

### `Services::Ledger::Query`
`Artist#balance` と `GET /api/artists/:id/ledger` の内部を実装。複式から契約書の外形へ射影する（各 journal_entry を `{ ledger_entry_id: je.id, artifact_id:, amount: artist_side_debit, issued_at:, gaze_event: {...} }` に変換）。

## コントローラ (`app/controllers/api/`)

- `Api::BaseController < ActionController::API` で `RecordNotFound` → 404, `RecordInvalid` → 422, `ArgumentError` → 400 の共通ハンドリング + シリアライザヘルパ。
- `Api::ArtistsController` — `create` / `balance` / `ledger`。
- `Api::ArtifactsController` — `create`。
- `Api::EncountersController` — `create` は `EncounterProcessor.call` を呼ぶだけ。`:issued` → 201、`:below_threshold` → 202。

ルーティング (`config/routes.rb`):
```ruby
namespace :api do
  resources :artists, only: [:create] do
    member do
      get :balance
      get :ledger
    end
  end
  resources :artifacts, only: [:create]
  resources :encounters, only: [:create]
end
mount ActionCable.server => "/cable"
```

## ActionCable

- `ArtistChannel` — `stream_for Artist.find(params[:artist_id])`。認証は契約書で保留なので TODO コメントでスタブ。
- broadcast payload は契約書 §Push Payload と完全一致。`narrative` は `"誰かがこの作品を #{duration}秒 凝視しました"`。

## テスト (`spec/`)

RSpec + FactoryBot + database_rewinder。`let!` 必須（カスタム cop）。

- **factories**: artist, artifact, gaze_event, account, journal_entry, ledger_line。
- **models**:
  - `JournalEntry` — 借方貸方不一致で validation が落ちる spec を必ず入れる（**複式の不変条件をテストで守る**）。
  - `LedgerLine` — 片側 0 制約。
  - `Account#balance`。
- **services**:
  - `IssuancePolicy` — 閾値境界 + amount 計算。
  - `EncounterProcessor` —
    - (a) 閾値超 → gaze_event + journal_entry + 2 lines 作成 + broadcast 発火 (`have_broadcasted_to`)。
    - (b) 閾値未満 → gaze_event のみ、journal_entry は増えない。
    - (c) artifact 不在 → `RecordNotFound`。
    - (d) **同じ idempotency_key で 2 回呼んでも journal_entry は 1 件だけ**（冪等性テスト、これ重要）。
    - (e) システム全体で `SUM(debit) == SUM(credit)` が常に成り立つことを invariant spec として 1 本書く。
- **requests** (`spec/requests/api/`): 契約書の全エンドポイントを網羅。JSON キー・ステータスコードが契約書と完全一致することを assert。
- **channels**: `ArtistChannel` subscribe。

## 実装ステップ（解説つき段階実行）

各ステップの冒頭で短い概念解説（3〜5 行）を提示し、コードを書き、`make rspec` で動作確認 → 次へ。

1. **Phase 0: primer 執筆** — `docs/banking-primer.md` を書きユーザーと読み合わせ。
2. **スキーマ** — Schemafile 作成 → `make db/schema/apply`。ここで「accounts / journal_entries / ledger_lines / gaze_events の 4 階建て」を図で説明。
3. **モデル + factory + model spec** — `JournalEntry` の validation で複式の不変条件を書く。このタイミングで「借方貸方とは」を解説。
4. **`IssuancePolicy` + spec** — 閾値と amount 計算だけ。純粋関数。
5. **`EncounterProcessor` + spec** — 複式取引の組み立てと idempotency。ここが銀行の心臓。解説比重を最大に。
6. **routes + `Api::BaseController` + 各 controller + request spec** — API 外形を契約書通りに組み、内部の複式構造を隠蔽する「射影」の概念を解説。
7. **`ArtistChannel` + broadcast 配線 + channel spec** — リアルタイム push。HUD に流れる narrative まで通す。
8. **lint / security** — `make rubocop` / `make brakeman` / `make bundler-audit` を緑に。

ユーザーが途中で「もっと解説して」「先に進んで」と言えるように、各ステップ終了時にいったん止まる運用にする。

## 検証 (end-to-end)

```bash
make setup                      # 初回のみ
make db/schema/apply
make rspec                      # 全 spec 緑、特に複式 invariant spec と idempotency spec
make rubocop
make brakeman
```

手動確認 (`make up` 後):
```bash
curl -X POST localhost:3000/api/artists -H 'Content-Type: application/json' \
  -d '{"handle":"akatsuki","display_name":"あかつき","public_key":"dummy"}'
curl -X POST localhost:3000/api/artifacts -H 'Content-Type: application/json' \
  -d '{"artist_id":1,"title":"月夜","origin_type":"url","origin_ref":"https://example.com/t.jpg"}'
# 同じ encounter を 2 回送って、balance が 1 回分しか増えないことを確認（冪等性）
curl -X POST localhost:3000/api/encounters -H 'Content-Type: application/json' \
  -d '{"artifact_id":1,"duration_seconds":4.2,"intensity_score":0.87,"observed_at":"2026-04-15T12:34:56Z","client_session_id":"anon-1"}'
curl -X POST localhost:3000/api/encounters -H 'Content-Type: application/json' \
  -d '{"artifact_id":1,"duration_seconds":4.2,"intensity_score":0.87,"observed_at":"2026-04-15T12:34:56Z","client_session_id":"anon-1"}'
curl localhost:3000/api/artists/1/balance
curl "localhost:3000/api/artists/1/ledger?limit=20"
```

## スコープ外（後続 PR）

- public_key 署名認証（ArtistChannel 含む）
- レート制限・不正検知
- `amount` 算出の正式仕様
- `intensity_score` 正規化
- エラーレスポンス形式の統一
- 複数通貨・手数料・為替などの発展的な会計概念
