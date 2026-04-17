# fuju-bank-backend 全体設計ドキュメント（MVP）

> **このドキュメントの位置付け**: `fuju-bank-backend`（銀行層）の MVP 実装方針を俯瞰するハブ。
> 個別タスク（`01-*.md` 以降）はこの overview の設計に従って実装される。

## 1. プロジェクト背景

### 1.1 fuju-bank とは

fuju-bank は「感情を担保とする中央銀行」であり、仮想通貨「ふじゅ〜」の発行・記帳・決済・配信を司る。
鑑賞者がアート作品の前で滞留し・視線を向け「魂を削られた」時間を、ふじゅ〜としてアーティストに還元する
というコンセプトを支える中央台帳。

### 1.2 3層アーキテクチャにおける位置付け

| 層 | リポジトリ例 | 責務 |
|---|---|---|
| 1層目（本リポジトリ）**銀行** | `fuju-bank-backend` | 発行・記帳・決済・配信の中央台帳 |
| 2層目 **マイニング** | `glyca-mining` 等 | ブラウザ内 MediaPipe で視線・滞留をエッジ解析、重み付け計算 |
| 3層目 **デモ SNS / 作家 HUD** | `glyca-client-web` 等 | タイムライン滞留でマイニング、作家 HUD へ push 通知 |

銀行層は他の2層から呼び出される **受け身のサービス**。小数点の重み付け計算はマイニング層が担い、
切り捨てた **整数値** だけが銀行に渡る。

### 1.3 ふじゅ〜の特性

- **単位**: 整数（`bigint`）。銀行内部は小数を扱わない。
- **発行起点**: `Artifact`（物理場所 or URL と紐付く）。
- **譲渡先**: `Artist`（ふじゅ〜の受け取り手）。
- **記録**: 「何秒魂を削られたか」「滞留時間」「視線強度」などのコンテキストを `metadata` に格納。
- **PayPay と銀行口座のハイブリッド + 仮想通貨**: 送金（PayPay 的） × 全発行履歴の台帳（仮想通貨的） × 口座残高（銀行的）。

---

## 2. 銀行層の責務と非責務

### 2.1 責務（MVP スコープ内）

1. `Artist` / `Artifact` / `Account` の CRUD 基盤
2. **発行（mint）**: `Artifact` から `Artist` への新規ふじゅ〜発行
3. **送金（transfer）**: `Artist` → `Artist` のふじゅ〜移動
4. 残高照会 / 取引履歴 API
5. `ArtistChannel` による `credit` イベントのリアルタイム配信
6. べき等性保証（`Idempotency-Key` による重複受信の吸収）
7. 統一エラーレスポンス形式

### 2.2 非責務（MVP 外 / 将来拡張）

- **認証・認可**: 別基盤で進行中。本リポジトリでは境界だけ定義し、各コントローラ／Channel に `TODO: 認証は将来拡張` を残す。
- **手数料**: 現状なし。将来は「手数料口座」を `accounts.kind` に足し、`ledger_entries` に1行追加するだけで実装可能。
- **鑑賞者ユーザー口座**: 現状は Artist のみモデル化。将来 `accounts.kind` に `user` を追加して拡張。
- **SNS Webhook / 外部通知**: 3層側のイベント受信は MVP では扱わない（必要なら別タスクで設計）。
- **日次残高突合ジョブ**: `accounts.balance_fuju`（キャッシュ）と `ledger_entries` の SUM を突合するジョブは MVP 外。整合性は DB トランザクションと CHECK 制約で担保。
- **CORS**: `rack-cors` はコメントアウトされたまま。MVP では設定不要（認証基盤側で扱う）。
- **JSON シリアライザ**: `alba` / `jbuilder` 等は入れず、プレーン Hash + `render json:` で通す。将来 `alba` を検討。

---

## 3. ドメインモデル

### 3.1 ER 図

```mermaid
erDiagram
    Artist ||--|| Account : "has_one (kind: artist)"
    Artist ||--o{ Artifact : "creates"
    Account ||--o{ LedgerEntry : "has_many"
    LedgerTransaction ||--|{ LedgerEntry : "has_many (>= 2)"
    Artifact ||--o{ LedgerTransaction : "mint source"

    Artist {
        bigint id PK
        string name
        string public_key "HUD接続用 (将来の署名検証で使用)"
        timestamps
    }

    Artifact {
        bigint id PK
        bigint artist_id FK "作成者 Artist"
        string title
        string location_url "nullable"
        string location_kind "enum: physical / url"
        timestamps
    }

    Account {
        bigint id PK
        bigint artist_id FK "nullable (system 発行口は NULL)"
        string kind "enum: system_issuance / artist"
        bigint balance_fuju "残高キャッシュ"
        timestamps
    }

    LedgerTransaction {
        bigint id PK
        string kind "enum: mint / transfer"
        string idempotency_key UK "ユニーク"
        bigint artifact_id FK "mint時のみ必須"
        string memo
        jsonb metadata "滞留秒数 / 視線強度 等"
        datetime occurred_at
        timestamps
    }

    LedgerEntry {
        bigint id PK
        bigint ledger_transaction_id FK
        bigint account_id FK
        bigint amount "借方正 / 貸方負 / SUM=0"
        timestamps
    }
```

### 3.2 エンティティ詳細

#### Artist
- ふじゅ〜の受け取り手。独自 ID + HUD 接続用 `public_key` を保持。
- `after_create` で対応する `Account`（`kind: "artist"`）を自動作成（`Artist` と `Account` は 1:1）。

#### Artifact
- 発行の起点。物理場所（美術館内の作品）または URL（Web 上の作品）と紐付く。
- `location_kind` enum: `physical` / `url`。`location_url` は `url` の場合に必須。
- 発行（mint）時には `Artifact` が必ず指定される。

#### Account
- 勘定口座の抽象化。`kind` enum で役割を区別。
  - `system_issuance`: ふじゅ〜の発行源（マイナス残高許容）。`artist_id` は NULL。システム初期化時に1行 seed。
  - `artist`: Artist 口座（マイナス残高禁止、`balance_fuju >= 0` CHECK 制約）。`artist_id` は必須。
- `balance_fuju` は `ledger_entries.amount` の SUM キャッシュ。**同一トランザクション内で entry 追加と同時更新** する。

#### LedgerTransaction（ヘッダ）
- 1 回の記帳イベント。`kind`（`mint` / `transfer`）で種別を持つ。
- `idempotency_key` はユニーク。重複受信時は既存レコードを返す。
- `metadata` JSONB には「滞留秒数」「視線強度」など、削られた魂のコンテキストを格納。
- `occurred_at` はマイニング層が観測した時刻（クライアント時刻）。`created_at` は銀行記帳時刻。

#### LedgerEntry（明細）
- 1 つの `LedgerTransaction` に対して **必ず 2 行以上** 存在。
- `amount`: 借方 = 正、貸方 = 負。1 トランザクション内で **`SUM(amount) = 0`** をモデル層で保証。
- 将来 DB 側の deferred constraint や `AFTER INSERT` トリガーで冪等化する余地あり。MVP はモデル層の検証で十分。

---

## 4. 記帳モデル（複式簿記）

### 4.1 設計判断の理由

「PayPay と銀行口座のハイブリッド、仮想通貨的な立ち位置」を素直に表現するため、
**複式簿記（entries テーブル）** を採用する。

- **監査性**: 全発行履歴が台帳として残る（Notion 記載の設計思想と合致）。
- **拡張性**: 手数料口座・プール口座・外部決済を「entry を追加するだけ」で表現できる。
- **整合性**: `SUM(entries.amount) = 0` を不変条件にすれば、1つの取引で失われる/生まれるふじゅ〜はない。

### 4.2 仕訳パターン

#### Mint（発行）

`POST /ledger/mint` で呼ばれる。`artifact_id` → `artist_id` に N ふじゅ〜を発行する。

```
ledger_transaction: kind=mint, artifact_id=X, idempotency_key=...
  entries:
    - account_id=<system_issuance>, amount=-N   (貸方: 発行口から出る)
    - account_id=<artist X's account>, amount=+N (借方: Artist に入る)
```

`accounts.balance_fuju` 更新:
- `system_issuance.balance_fuju -= N`（負の値になってよい。CHECK 制約対象外）
- `artist_account.balance_fuju += N`

#### Transfer（送金）

`POST /ledger/transfer` で呼ばれる。Artist A → Artist B に N ふじゅ〜を送る。

```
ledger_transaction: kind=transfer, artifact_id=NULL, idempotency_key=...
  entries:
    - account_id=<A's account>, amount=-N (貸方: 送り手から出る)
    - account_id=<B's account>, amount=+N (借方: 受け手に入る)
```

`accounts.balance_fuju` 更新:
- `A.balance_fuju -= N`（`A.balance_fuju - N < 0` なら残高不足エラーで中断）
- `B.balance_fuju += N`

### 4.3 不変条件

| 制約 | 実装場所 |
|---|---|
| `SUM(entries.amount) = 0` per transaction | モデル層 `before_save` validation（`LedgerTransaction`） |
| `accounts.balance_fuju >= 0 WHERE kind = 'artist'` | DB の CHECK 制約（部分制約） |
| `ledger_transactions.idempotency_key` unique | DB のユニーク制約 |
| mint/transfer 処理の原子性 | `ActiveRecord::Base.transaction` で囲む |

---

## 5. API 境界

### 5.1 エンドポイント一覧

| Method | Path | 用途 | 認証 |
|---|---|---|---|
| `POST` | `/artists` | Artist 作成 | TODO: 将来拡張 |
| `GET` | `/artists/:id` | Artist 情報 + 残高取得 | TODO: 将来拡張 |
| `GET` | `/artists/:id/transactions` | 取引履歴（mint / transfer 統合） | TODO: 将来拡張 |
| `POST` | `/artifacts` | Artifact 作成 | TODO: 将来拡張 |
| `GET` | `/artifacts/:id` | Artifact 情報 | TODO: 将来拡張 |
| `POST` | `/ledger/mint` | 発行（マイニング層から） | TODO: 将来拡張 |
| `POST` | `/ledger/transfer` | 送金（Artist → Artist） | TODO: 将来拡張 |

### 5.2 共通レスポンス形式

#### 成功時

```json
{
  "data": { /* リソース本体 */ }
}
```

または単純なリソースレスポンス（`render json: artist_hash`）。
MVP ではラッパー（`data`）を強制せず、各エンドポイントでプレーン Hash を返す方針。

#### エラー時

```json
{
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "残高が不足しています"
  }
}
```

`ApplicationController#rescue_from` で共通実装する（タスク `01-setup-api-error-handling.md`）。

| `error.code` | HTTP | 用途 |
|---|---|---|
| `VALIDATION_FAILED` | 422 | バリデーション失敗 |
| `NOT_FOUND` | 404 | リソース不在 |
| `INSUFFICIENT_BALANCE` | 422 | 送金時の残高不足 |
| `IDEMPOTENCY_CONFLICT` | 409 | 同一 `idempotency_key` で異なる payload |
| `INTERNAL_ERROR` | 500 | 想定外エラー |

### 5.3 べき等性

- `POST /ledger/mint` と `POST /ledger/transfer` は **`Idempotency-Key` ヘッダ（または body 内 `idempotency_key`）必須**。
- `ledger_transactions.idempotency_key` にユニーク制約。
- 同一キーの重複受信時は既存トランザクションをそのまま返す（HTTP 200 + 既存リソース）。
- 同一キーで payload が異なる場合は `409 IDEMPOTENCY_CONFLICT`。

---

## 6. ActionCable チャネル設計

### 6.1 `ArtistChannel`

```ruby
# app/channels/artist_channel.rb
class ArtistChannel < ApplicationCable::Channel
  def subscribed
    # TODO: 認証は将来拡張（public_key 署名検証）
    artist = Artist.find_by(id: params[:artist_id])
    if artist.nil?
      reject
    else
      stream_for artist
    end
  end
end
```

- **接続**: クライアント（作家 HUD PWA）は `artist_id` をクエリ or subscribe params で渡す。
- **broadcast 先**: mint / transfer の **受け手 Artist の Channel** に push。
- **MVP の認証**: `artist_id` のみで identify（簡易）。将来 `public_key` 署名検証を追加する TODO を残す。

### 6.2 broadcast ペイロード

```json
{
  "type": "credit",
  "amount": 15,
  "transaction_id": 42,
  "transaction_kind": "mint",
  "artifact_id": 7,
  "from_artist_id": null,
  "metadata": { "dwell_seconds": 12, "gaze_strength": 0.8 }
}
```

- `type`: MVP は `credit` のみ（受け手への入金通知）。将来 `debit` 等を追加。
- `transaction_kind`: `mint` / `transfer`。
- `from_artist_id`: transfer の場合のみ。mint は `null`。

### 6.3 broadcast フック

`Ledger::Mint` / `Ledger::Transfer` サービスが成功したら、**受け手 Artist の Account に紐づく Artist** に
`ArtistChannel.broadcast_to(artist, payload)` する（タスク `20-broadcast-on-credit.md`）。

---

## 7. スキーマ管理方針（Ridgepole）

- Rails migration は **使わない**。全テーブル定義は `db/Schemafile` に記述。
- `db/Schemafile` はサブファイル化してメンテナンス性を保つ（タスク `02-setup-schemafile-base.md`）。
  ```
  db/Schemafile                     # ルート。require のみ
  db/schema/artists.rb
  db/schema/artifacts.rb
  db/schema/accounts.rb
  db/schema/ledger_transactions.rb
  db/schema/ledger_entries.rb
  ```
- 反映コマンド: `make db/schema/apply`（dev + test）。

---

## 8. 個別タスク一覧（実装順序）

> 依存関係は `依存: #xx` で表記。並行可能なタスクは同じ Phase にまとめる。
> 各タスクは **1 PR = 1 タスク** 粒度。ベースブランチは `develop`。

### Phase 0: 基盤整備（並行可）

| # | タスク | 依存 |
|---|---|---|
| 01 | [共通エラーレスポンス / rescue_from 実装](./01-setup-api-error-handling.md) | なし |
| 02 | [Schemafile サブファイル分割](./02-setup-schemafile-base.md) | なし |
| 03 | [Idempotency-Key concern](./03-idempotency-concern.md) | #01 |

### Phase 1: スキーマ定義（`#02` 完了後、並行可）

| # | タスク | 依存 |
|---|---|---|
| 04 | [artists テーブル](./04-add-artists-table.md) | #02 |
| 05 | [artifacts テーブル](./05-add-artifacts-table.md) | #02, #04 |
| 06 | [accounts テーブル + system 口座 seed](./06-add-accounts-table.md) | #02, #04 |
| 07 | [ledger_transactions テーブル](./07-add-ledger-transactions-table.md) | #02, #05 |
| 08 | [ledger_entries テーブル](./08-add-ledger-entries-table.md) | #02, #06, #07 |

### Phase 2: モデル層

| # | タスク | 依存 |
|---|---|---|
| 09 | [Artist モデル + Account bootstrap](./09-artist-model-and-account-bootstrap.md) | #04, #06 |
| 10 | [Artifact モデル](./10-artifact-model.md) | #05, #09 |

### Phase 3: サービス層（Ledger）

| # | タスク | 依存 |
|---|---|---|
| 11 | [Ledger::Mint サービス](./11-ledger-service-mint.md) | #06, #07, #08, #09, #10 |
| 12 | [Ledger::Transfer サービス](./12-ledger-service-transfer.md) | #06, #07, #08, #09, #11 |

### Phase 4: コントローラ層

| # | タスク | 依存 |
|---|---|---|
| 13 | [POST /artists](./13-artists-controller-create.md) | #01, #09 |
| 14 | [GET /artists/:id](./14-artists-controller-show-balance.md) | #01, #09 |
| 15 | [Artifacts CRUD](./15-artifacts-controller.md) | #01, #10 |
| 16 | [POST /ledger/mint](./16-mint-endpoint.md) | #01, #03, #11 |
| 17 | [POST /ledger/transfer](./17-transfer-endpoint.md) | #01, #03, #12 |
| 18 | [GET /artists/:id/transactions](./18-transactions-list-endpoint.md) | #01, #09, #11, #12 |

### Phase 5: リアルタイム配信

| # | タスク | 依存 |
|---|---|---|
| 19 | [ArtistChannel 骨組み](./19-artist-channel-skeleton.md) | #09 |
| 20 | [mint / transfer 時の broadcast フック](./20-broadcast-on-credit.md) | #11, #12, #19 |

### 依存グラフ概要

```
#01 ┐
    │                                                  ┌─ #13, #14, #18
#02 ┼─ #04 ─ #06 ─┐                                    │
    │       │    ├─ #09 ─┬─ #10 ─┬─ #11 ─┬─ #12 ──────┤
    │       #05 ─┤       │       │       │            │
    │             │       │       │       │            ├─ #16
    │       #07 ─┤       │       #15 ←──┘            │
    │            └─ #08 ─┘                            └─ #17
    │
    │              #09 ─ #19 ─┬─ #20
    │                          │
    │              #11, #12 ──┘
    │
    └─ #03 ─ (#16, #17 で使用)
```

- Phase 0（#01 / #02 / #03）はお互い独立（#03 は #01 のみ依存）。
- Phase 1 スキーマは `#02` 完了後に並行可。FK 依存順は `#04 → #05/#06 → #07 → #08`。
- `#11` は `#10`（Artifact モデル）に依存、`#12` は `#11` 実装済みの `LedgerTransaction`/`LedgerEntry` モデルを流用。
- コントローラ層（#13〜#18）は共通エラーハンドラ `#01` とそれぞれの上流モデル／サービスに依存。
- `#19` / `#20` は Artist モデル（#09）と Ledger サービス（#11, #12）の完成後に実装。

---

## 9. 開発フロー / 運用方針

### 9.1 ブランチ戦略

- `develop` をベースに `feat/xxx` を切る。1 PR = 1 タスク。
- PR マージで `develop → main` のリリース PR が自動更新される（既存 GitHub Actions）。

### 9.2 テスト

- RSpec + FactoryBot。`make rspec ARGS=...` で部分実行。
- `bullet` で N+1 検出。取引履歴系エンドポイントでは特に注意。
- `database_rewinder` で各テスト後にクリーン。

### 9.3 Lint / セキュリティ

- `make rubocop` / `make rubocop/fix` は毎回。
- `make brakeman` / `make bundler-audit` は PR で確認。

### 9.4 Ridgepole 運用

- スキーマ変更は `db/Schemafile` または `db/schema/*.rb` の編集 → `make db/schema/apply` で反映。
- Rails migration は一切使わない（生成コマンドも禁止）。

---

## 10. 参照

- `CLAUDE.md`: プロジェクトルール、Docker / Makefile / RuboCop 規約
- NxTECH Workspace: 「プロダクト落とし所 v5: 3層アーキテクチャ」設計思想
- [Ridgepole](https://github.com/ridgepole/ridgepole)
- [Solid Queue / Solid Cache / Solid Cable](https://github.com/rails/solid_queue)
