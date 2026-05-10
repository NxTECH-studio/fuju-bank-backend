# server-bank-23: 送金時 MFA 解消経路の仕様確定

> 本タスクは Rails 製の **fuju-bank-backend** リポジトリ側で実施する仕様確認・実装タスク。
> クライアント計画書 `docs/tasks/client-bank-22-money-transfer.md` の Open Question 4
> （送金時 `MFA_REQUIRED` の verify 経路）に対応する。
> 計画書ファイル自体はクライアント計画書と一元参照したいため `fuju-bank-app/docs/tasks/` に置く。

## 概要

`POST /ledger/transfer` が `MFA_REQUIRED` を返した場合に、クライアントがどの API で MFA を
verify して **同じ idempotency_key で再送できるか** の仕様を確定し、バックエンド側に必要な
実装変更があれば加える。クライアント側は `LedgerRepository.transfer(retryKey = ...)` で再送
ロジックは既に組まれているため、**「verify 後の access_token / コンテキストが MFA 検証済み
として扱われる」** ことが確認できれば本タスクは仕様確認のみで closeable。

## 背景・目的

- `POST /ledger/transfer` は仕様上 `MFA_REQUIRED` を返しうる（README §「ApiErrorCode」参照、
  `MFA_REQUIRED`: "MFA 未検証トークンで MFA 必須 action を叩いた"）。
- ただしクライアント側は **どの API で MFA を verify すれば transfer を再送可能になるのか**
  の仕様を持っていない。候補は以下:
  - 候補 A: AuthCore `/v1/auth/mfa/verify` に **既存 access_token + TOTP** を渡し、
    新しい access_token を得る（= MFA 検証済みフラグつき）。これを使って再 transfer する。
  - 候補 B: bank 側に `/v1/ledger/mfa/verify` のような action-scoped MFA verify を新設し、
    短期チケットを発行 → transfer に同梱する。
  - 候補 C: AuthCore `/v1/auth/mfa/verify` の現行仕様（`pre_token` 必須）と整合しないため、
    **送金前に再ログイン相当のフローを挟む**（UX 大幅劣化）。
- 現状 AuthCore の `/v1/auth/mfa/verify` は **login 時の `pre_token` 用** であり、
  ログイン後に「MFA 検証だけ追加で行いたい」用途を持っていない可能性がある。
  → AuthCore 側仕様の確認が必要。

## スコープ

### 含む

- AuthCore (`fuju-system-authentication`) と bank (`fuju-bank-backend`) の現行仕様確認
- 採用する経路（A / B / C）の決定
- 採用方針に応じた実装（AuthCore 側で「MFA step-up verify」エンドポイントが必要なら追加、
  bank 側で短期チケット検証ロジックが必要なら追加）
- request spec / 結合動作確認

### 含まない

- `POST /ledger/transfer` 本体の核心ロジック改修（idempotency / 残高更新）
- MFA セットアップ（enroll）フロー（`client-bank-21-signup-with-mfa-setup` で済）

## 候補と評価

### 候補 A: AuthCore に「step-up MFA verify」を追加（推奨）

```
POST /v1/auth/mfa/step-up
Authorization: Bearer <現行 access_token>
Body: { "code": "123456" }  // または recovery_code
→ 200 { "access_token": "<新トークン: mfa_verified=true>", ... }
```

- 既存 `/v1/auth/mfa/verify`（`pre_token` 用）と並列に新設。
- 既存 access_token が valid な前提で「MFA を追加検証した新トークン」に差し替える。
- bank 側 introspection が `mfa_verified=true` を見て transfer を許可する。
- **長所**: AuthCore 責務（認証）に沿う。bank 側に MFA ロジックを持ち込まない。
- **短所**: AuthCore 側に新エンドポイント追加が必要。

### 候補 B: bank 側 action-scoped MFA verify

```
POST /ledger/mfa/verify
Authorization: Bearer <access_token>
Body: { "code": "123456", "action": "transfer", "ticket_ttl": 60 }
→ 200 { "ticket": "<短期チケット>" }

POST /ledger/transfer
Headers: Idempotency-Key, X-MFA-Ticket
→ 200 ...
```

- bank が AuthCore に TOTP 検証を委譲（internal API か AuthCore SDK 経由）。
- **長所**: AuthCore 側 API 追加不要。送金専用に設計できる。
- **短所**: bank 側に MFA verify ロジックが入り込む。AuthCore との責務分離が崩れる。

### 候補 C: 再ログインフロー

- ユーザーに再ログインさせて MFA 検証済み access_token を取らせる。
- **長所**: 仕様変更ゼロ。
- **短所**: UX 最悪。送金のたびに再ログインは現実的でない。MVP には不適。

### 推奨: **候補 A**

- 認証は AuthCore に集中させる方針（既存設計）と整合。
- bank 側コード変更は **introspection レスポンスの `mfa_verified` を読むだけ**（既に読んでる
  可能性が高い）。
- クライアント側 `AuthApi.mfaStepUp(...)` 相当を追加するだけで済む。

## 仕様確認チェックリスト（最初にやること）

実装に入る前に、以下を fuju-system-authentication / fuju-bank-backend のコードと README で確認:

- [ ] AuthCore `/v1/auth/mfa/verify` は `pre_token` のみ受けるか、access_token も受けるか
- [ ] AuthCore introspection レスポンスに `mfa_verified` フィールドがあるか
- [ ] bank `POST /ledger/transfer` が introspection 結果のどのフィールドで MFA 必須判定を
      しているか（`mfa_required` ユーザー属性 × `mfa_verified` トークン属性、等）
- [ ] 「MFA 必須 action」の定義はどこにあるか（hardcoded? config? per-endpoint?）

→ 確認結果次第で、以下の「実装ステップ」が大幅に変わる可能性あり。

## API 仕様案（候補 A 採用時）

### AuthCore: 新規エンドポイント

```
POST /v1/auth/mfa/step-up
Authorization: Bearer <access_token>  ※ 現行の MFA 未検証トークン
Content-Type: application/json

Body:
  { "code": "123456" }            // TOTP
  または
  { "recovery_code": "XXXX-XXXX" } // リカバリコード

Response 200:
  {
    "access_token": "<新 access_token: mfa_verified=true>",
    "expires_in": 900,
    "token_type": "Bearer"
  }
  // refresh_token は HttpOnly cookie で更新（既存と同じ）

Response 401:
  - INVALID_CREDENTIALS / TOTP_CODE_INVALID / RECOVERY_CODE_INVALID
Response 429:
  - RATE_LIMIT_EXCEEDED（連続誤入力）
```

### bank: 変更なし（想定）

- 既存 `POST /ledger/transfer` は introspection の `mfa_verified=true` を見て透過的に通る。
- `MFA_REQUIRED` を返す条件は既存ロジックのまま。

### クライアント側の流れ（参考）

```
1. POST /ledger/transfer → MFA_REQUIRED
2. UI で TOTP 入力させる
3. POST /v1/auth/mfa/step-up { code } → 新 access_token
4. TokenStorage に新 access_token を上書き
5. POST /ledger/transfer（同じ idempotency_key で再送）→ 200
```

## 影響範囲

### 候補 A 採用の場合

- **fuju-system-authentication（AuthCore）**:
  - `POST /v1/auth/mfa/step-up` controller / route 追加
  - 既存 `mfa_verify` のサービスクラスを再利用 + 新 access_token 発行
  - request spec
- **fuju-bank-backend**:
  - 変更なし（仕様確認のみ）
  - 既に `mfa_verified` を introspection で見ているなら 0 行変更
  - 見ていないなら `before_action` を追加して MFA 必須 action を保護
- **fuju-bank-app（クライアント）**:
  - `AuthApi.mfaStepUp(code, recoveryCode)` 追加
  - `LedgerRepository.transfer` の `MfaRequired` ハンドリング経路に組み込み
  - これは `client-bank-22` の Phase 2 / Phase 4 で実装

### 候補 B 採用の場合

- **fuju-bank-backend** に新エンドポイント / チケット管理 / AuthCore TOTP 検証委譲が必要 → 工数大

## バリデーション / エラー

| ケース | HTTP | code |
|---|---|---|
| `code` / `recovery_code` 欠落 | 422 | `VALIDATION_FAILED` |
| TOTP コード不正 | 401 | `TOTP_CODE_INVALID` |
| リカバリコード不正 | 401 | `RECOVERY_CODE_INVALID` |
| access_token 無効 | 401 | `UNAUTHENTICATED` / `TOKEN_EXPIRED` |
| MFA 未有効ユーザー | 400 | `MFA_NOT_ENABLED` |
| 連続誤入力 | 429 | `RATE_LIMIT_EXCEEDED` |

## テスト方針（候補 A）

- AuthCore request spec: `POST /v1/auth/mfa/step-up` のハッピーパス + 各 error code
- AuthCore service spec: 既存 `MfaVerifyService` の再利用テスト
- bank 結合テスト: MFA 必須ユーザーで transfer → MFA_REQUIRED → step-up → transfer 成功
  （staging 環境での手動確認で OK）

## 完了条件

1. 採用方針（A / B / C）が決まり、本ドキュメントに明記されている
2. 候補 A 採用時: AuthCore に `POST /v1/auth/mfa/step-up` がマージされ staging で動作
3. クライアント側 `AuthApi.mfaStepUp` が呼べる状態（`client-bank-22` の Phase 2 が
   アンブロックされる）
4. MFA 必須テストアカウントで「transfer → MFA_REQUIRED → step-up → transfer 成功」が
   end-to-end で動作

## Open Questions

1. **AuthCore の現行 `/v1/auth/mfa/verify` を access_token 受け入れに拡張する選択肢はあるか**
   - 既存エンドポイントを増築すると login フローと混線するリスクがあるため、**新エンドポイント
     `/v1/auth/mfa/step-up` を切るほうが安全** と考える。
2. **`mfa_verified` フラグの寿命**
   - 一度 step-up したら、その access_token の expiry まで送金 OK にするか、それとも transfer 1
     回ごとに step-up を要求するか。
   - 推奨: access_token expiry までは送金 OK（UX 重視）。短くしたければ step-up で発行する
     access_token の TTL を短くする（例: 5 min）。
3. **bank 側の「MFA 必須 action」リストの設定方法**
   - 現状 hardcoded か config か未確認。config 化されていれば `transfer` を追加するだけ。
4. **MFA 未有効ユーザーが送金しようとした場合**
   - `MFA_NOT_ENABLED` を返すか、そもそも `MFA_REQUIRED` を返さない（MFA 未有効ユーザーには
     transfer を素通りさせる）かを確認。MVP のセキュリティ要件次第。
5. **このタスクが先に終わらないとクライアント `client-bank-22` がリリースできないか**
   - **NO**。クライアント側は MFA 経路を `TODO` プレースホルダにしておけば、MFA 必須ユーザーが
     送金できないだけで他のユーザーは送金 OK。本タスクは並行進行で良い。

## 関連タスク

- クライアント側: [`docs/tasks/client-bank-22-money-transfer.md`](./client-bank-22-money-transfer.md)
  （Open Question 4 に対応）
- 関連バックエンドタスク: [`docs/tasks/server-bank-22-recipient-resolution-api.md`](./server-bank-22-recipient-resolution-api.md)
