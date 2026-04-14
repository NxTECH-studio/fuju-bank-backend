# fuju-bank API契約

本ドキュメントは fuju-bank（銀行層）と他の2層（マイニング層、デモSNS層）の境界面を定義する。

この契約はチームの並列開発の足場であり、変更時は3層すべての担当者と合意すること。

## エンドポイント一覧

| メソッド | パス | 呼び出し元 | 目的 |
|---|---|---|---|
| `POST` | `/api/artists` | SNS | 作家の口座開設 |
| `POST` | `/api/artifacts` | SNS | 作品の登録（発行対象の設定）|
| `POST` | `/api/encounters` | マイニング | proof-of-feeling の提出 |
| `GET` | `/api/artists/:id/balance` | SNS | 残高照会 |
| `GET` | `/api/artists/:id/ledger` | SNS | 受け取った発行履歴の一覧 |
| `WS` | `/cable` | SNS (HUD) | リアルタイム通知 (`ArtistChannel`) |

---

## POST /api/artists

作家の口座を開設する。

### Request

```json
{
  "handle": "akatsuki",
  "display_name": "あかつき",
  "public_key": "-----BEGIN PUBLIC KEY-----\n..."
}
```

### Response (201)

```json
{
  "artist_id": 42,
  "handle": "akatsuki",
  "display_name": "あかつき",
  "created_at": "2026-04-15T12:34:56Z"
}
```

---

## POST /api/artifacts

作品を登録する。ふじゅ〜の発行対象になる。

### Request

```json
{
  "artist_id": 42,
  "title": "月夜",
  "origin_type": "url",
  "origin_ref": "https://example.com/tsukiyo.jpg",
  "description": "任意"
}
```

`origin_type` は `"physical"` | `"url"`。`physical` の場合 `origin_ref` は場所スラッグ（例: `"nxtech-2026-04/slot-3"`）。

### Response (201)

```json
{
  "artifact_id": 128,
  "artist_id": 42,
  "title": "月夜",
  "origin_type": "url",
  "origin_ref": "https://example.com/tsukiyo.jpg"
}
```

---

## POST /api/encounters

マイニングシステムから proof-of-feeling を提出する。**このエンドポイントが銀行層の中核**。

検証ロジック:
1. `duration_seconds` が閾値（デフォルト 3.0秒）以上
2. `intensity_score` が閾値（デフォルト 0.3）以上
3. `artifact_id` が存在する

条件を満たした場合、以下が実行される:
1. `gaze_events` に insert
2. `ledger_entries` に insert（amount は duration × intensity から算出）
3. `ArtistChannel` 経由で作家HUDに push

### Request

```json
{
  "artifact_id": 128,
  "duration_seconds": 4.2,
  "intensity_score": 0.87,
  "observed_at": "2026-04-15T12:34:56Z",
  "client_session_id": "anon-9f8e7d6c"
}
```

### Response (201) — 発行成功

```json
{
  "status": "issued",
  "gaze_event_id": 1024,
  "ledger_entry_id": 998,
  "amount": 15
}
```

### Response (202) — 閾値未満（記録のみ、発行なし）

```json
{
  "status": "below_threshold",
  "gaze_event_id": 1024
}
```

---

## GET /api/artists/:id/balance

作家の累積残高を返す。

### Response (200)

```json
{
  "artist_id": 42,
  "balance": 1847
}
```

---

## GET /api/artists/:id/ledger

作家が受け取った発行履歴の一覧を返す。ページング対応。

### Request

`GET /api/artists/42/ledger?limit=20&before=2026-04-15T00:00:00Z`

### Response (200)

```json
{
  "entries": [
    {
      "ledger_entry_id": 998,
      "artifact_id": 128,
      "amount": 15,
      "issued_at": "2026-04-15T12:34:56Z",
      "gaze_event": {
        "duration_seconds": 4.2,
        "intensity_score": 0.87
      }
    }
  ],
  "has_more": false
}
```

---

## WS /cable — ArtistChannel

作家HUD専用のリアルタイムチャネル。作家ごとに subscribe する。

### Subscribe

```json
{
  "command": "subscribe",
  "identifier": "{\"channel\":\"ArtistChannel\",\"artist_id\":42}"
}
```

認証は public_key ベースの署名トークンを想定（詳細は実装時に確定）。

### Push Payload

`POST /api/encounters` で発行が発生した瞬間に、該当作家に以下が push される。

```json
{
  "type": "ledger_issued",
  "ledger_entry_id": 998,
  "artifact": {
    "id": 128,
    "title": "月夜"
  },
  "amount": 15,
  "narrative": "誰かがこの作品を 4.2秒 凝視しました",
  "issued_at": "2026-04-15T12:34:56Z"
}
```

`narrative` は作家HUD上に OS風の通知として表示される一文。

---

## 今後の検討事項

- [ ] 認証方式の確定（public_key 署名 or OAuth2 or 簡易トークン）
- [ ] `amount` 算出ロジックの正式仕様（現状は `duration × intensity ×係数` の暫定案）
- [ ] レート制限・不正検知（同一 `client_session_id` からの過度な連続提出）
- [ ] マイニング側が返す `intensity_score` の標準化（MediaPipe の出力をどう正規化するか）
- [ ] エラーレスポンス形式の統一
