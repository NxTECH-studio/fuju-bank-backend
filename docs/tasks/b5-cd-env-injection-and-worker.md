# B5: 既存 CD への AUTHCORE_* 注入 / Solid Queue worker / ドキュメント更新

## メタ情報

- **Phase**: 1
- **並行起動**: ⚠️ B1 / B2 と **セット PR が望ましい**（先に merge すると本番 boot で KeyError）
- **依存**: B4 で AUTHCORE_BASE_URL / client_id / secret / 公開鍵が確定していること
- **同期点**: なし（インフラ作業）

## 概要

bank backend は既に `https://api.fujupay.app` で稼働中。CD は `.github/workflows/cd.yml` が main push で Tailscale + SSH 経由 Proxmox CT に入り `docker compose -p fuju-bank-prod -f compose.prod.yml up -d --build` する仕組み。本タスクは:

1. cd.yml と compose.prod.yml に AUTHCORE_* ENV を注入
2. Solid Queue worker サービスを compose に追加（無ければ）
3. Solid Cable のテーブル作成手順を runbook 化
4. CLAUDE.md の旧デプロイ記述を実態に修正

## 背景・目的

- B1 / B2 を merge すると `AUTHCORE_JWT_PUBLIC_KEY` 等が読まれて起動時 `KeyError` で落ちる → セット PR か、先に B5 merge が必須。
- Solid Queue / Solid Cable は Gemfile に居るが、本番で worker プロセスが立っていない可能性が高い（compose.prod.yml に独立 service なし）。

## 影響範囲

- ファイル:
  - `.github/workflows/cd.yml`
  - `compose.prod.yml`
  - `CLAUDE.md`
  - 新規 `docs/runbooks/deploy.md`
- GitHub repo settings: Secrets / Variables 追加
- 本番インフラ: 初回マイグレーション (Solid Cable) を 1 回実行

## 現状（2026-05-06 時点・着手前のスナップショット）

実装に入る前に必読。前提が初稿時点と変わっている。

### AuthCore 本番デプロイ状態

- **稼働中**: `https://auth.fujupay.app/`（タスク初稿の `authcore.fujupay.app` ではない、サブドメインは `auth`）
- 疎通確認済み: `GET /healthz` → 200 / `POST /v1/auth/introspect`（Basic Auth 無し）→ 401 / `GET /v1/auth/introspect` → 405
- JWKS endpoint なし (`/v1/.well-known/jwks.json` → 404)。**公開鍵は env 経由配布のみ**（`fuju-system-authentication/keys/jwt.public.pem` に PEM 実体がある）
- AuthCore コードでは `iss="authcore"` / `aud="authcore"` の両方が `cmd/server/main.go:58-64` で **hardcode**。bank の `config/initializers/authcore.rb` のデフォルトと一致するので `AUTHCORE_EXPECTED_*` の登録は省略可

### bank client 登録（**ハッカソン文脈で妥協**）

- AuthCore に `clients` テーブル管理用の admin endpoint / seed CLI / migration **はいずれも無い**。新規 client を作るには Go CLI 追加 or psql 直 INSERT が必要
- AuthCore には既に **`OAuthTest` テスト client が seed 済み**:
  - `client_id` = `clientfortest`
  - `client_secret` = `passwordfortest`
- ハッカソン用途として、専用 client (`fuju-bank-backend`) を作らずに `clientfortest` をそのまま流用する判断（2026-05-06 ユーザー合意）。本番運用に切り替える場合は ⚠️ 別途 seed が必要

### GitHub Secrets / Variables の登録状況

| 名前 | スコープ | 値 / 状態 |
|---|---|---|
| `AUTHCORE_BASE_URL` | Org Variable | ✅ `https://auth.fujupay.app/`（末尾 `/` あり、`URI.join` で吸収されるので OK） |
| `AUTHCORE_CLIENT_ID` | Repo Variable | ✅ `clientfortest` |
| `AUTHCORE_CLIENT_SECRET` | Repo Secret | ✅ `passwordfortest` |
| `JWT_PUBLIC` | Org Secret | ✅ 登録済（**注: 名前は `AUTHCORE_JWT_PUBLIC_KEY` ではなく `JWT_PUBLIC`**。AuthCore の公開鍵は bank/mining/SNS で共通なので Org-level に 1 個で済ませる方針） |
| `AUTHCORE_EXPECTED_AUDIENCE` | — | ❌ 未登録（デフォルト `"authcore"` と一致するので不要） |
| `AUTHCORE_EXPECTED_ISSUER` | — | ❌ 未登録（同上） |

### cd.yml / compose.prod.yml の現状

- `cd.yml` は既に `secrets.AUTHCORE_JWT_PUBLIC_KEY` を参照する形になっている（PR #78 / commit `3dde3a4`）が、**Org Secret 名は `JWT_PUBLIC`** なので **このままでは空文字が流れる**。マッピング修正が必須
- `compose.prod.yml` の `web.environment:` には `AUTHCORE_JWT_PUBLIC_KEY: ${AUTHCORE_JWT_PUBLIC_KEY}` だけ既に入っている。残り 3 つ (`BASE_URL` / `CLIENT_ID` / `CLIENT_SECRET`) は未追加
- `worker` service は未定義

### main / develop のズレ

- 直近の本番 CD run は 2026-04-28（PR #72）まで。PR #73〜#81（B1 / B2 / B3 / B5 関連の cd.yml 変更含む）は **すべて develop までで main 未 merge**
- 本タスクの PR を merge した後、別途 release PR で `develop → main` を流さないと本番には何も届かない

## 実装ステップ

1. **GitHub Secrets / Variables 登録**: ✅ 完了済（上記表参照）。**追加作業なし**

2. **`cd.yml` 更新**:
   - `env:` の `AUTHCORE_JWT_PUBLIC_KEY` を `${{ secrets.JWT_PUBLIC }}` に変更（Org Secret 名のマッピング）
   - `env:` に新規追加:
     ```yaml
     AUTHCORE_BASE_URL: ${{ vars.AUTHCORE_BASE_URL }}
     AUTHCORE_CLIENT_ID: ${{ vars.AUTHCORE_CLIENT_ID }}
     AUTHCORE_CLIENT_SECRET: ${{ secrets.AUTHCORE_CLIENT_SECRET }}
     ```
   - `appleboy/ssh-action` の `envs:` リストに 3 つ追加
   - `script:` 内 `export` 行に 3 つ追加
   - PEM 改行問題は **PEM 直貼り運用** で進める（Org Secret `JWT_PUBLIC` に既に直貼り済の前提）。base64 経由は不採用

3. **`compose.prod.yml` 更新**:
   - `web.environment:` に 3 行追加:
     ```yaml
     AUTHCORE_BASE_URL: ${AUTHCORE_BASE_URL}
     AUTHCORE_CLIENT_ID: ${AUTHCORE_CLIENT_ID}
     AUTHCORE_CLIENT_SECRET: ${AUTHCORE_CLIENT_SECRET}
     ```
   - `worker` service の追加は **ハッカソンでは判断保留**。現状 send/mint で Active Job を使っていないなら無くても動く。要否は Gemfile/コードを覗いて決める。Solid Cable のテーブル作成は Schemafile に既にあれば不要

4. **runbook 作成** (`docs/runbooks/deploy.md`): **ハッカソンでは省略可**。本番運用に切り替えるタイミングで書く

5. **CLAUDE.md 更新**:
   - 「デプロイ: 旧スキーム」を「GitHub Actions cd.yml + docker compose on Proxmox CT (Tailscale + SSH)」に書き換え
   - 旧デプロイ残骸ディレクトリの扱いは判断保留（無害なら残す）

## 検証チェックリスト

- [ ] cd.yml の dry-run（`act` or feature branch push）で `AUTHCORE_BASE_URL` / `CLIENT_ID` / `CLIENT_SECRET` / `JWT_PUBLIC_KEY` の 4 つが渡る
- [ ] 本番 web コンテナで `printenv | grep AUTHCORE` で 4 つ見える
- [ ] B1 / B2 と一緒に main へ流して本番 boot が成功する
- [ ] `https://api.fujupay.app/up` が 200
- [ ] `script/check_authcore.rb` を本番 base_url で叩いて register/login/introspect が緑
- [ ] CLAUDE.md がデプロイ手段の実態と一致

## ⚠️ 本番運用化する際の TODO（ハッカソン後）

- `clientfortest` / `passwordfortest` を捨て、`fuju-bank-backend` 専用 client を AuthCore に seed
- AuthCore に seed CLI を PR で追加（mining / SNS の client 追加でも使う）
- `docs/runbooks/deploy.md` を起こす
- worker service の要否を再評価（Active Job 利用が出てきたら追加）

## 議論の経緯（2026-05-06 セッションでの決定事項）

実装着手時に「なぜそうなっているか」が辿れるように、セッションでの判断とその理由を残す。

### URL のサブドメインが `auth` であって `authcore` ではない

- タスク初稿は `https://authcore.fujupay.app` だったが、Org Variable 登録時に `https://auth.fujupay.app/` で確定
- 末尾スラッシュは bank の `Authcore::IntrospectionClient#post_introspect` が `URI.join(base_url, "/v1/auth/introspect")` で結合するため吸収される（`URI.join` の挙動: 第二引数が絶対パスなら base のパス部を置き換える）。検証済み

### Org Secret 名が `AUTHCORE_JWT_PUBLIC_KEY` ではなく `JWT_PUBLIC`

- AuthCore の公開鍵は **bank / mining / SNS の 3 リポジトリすべてで同じ値を読む**
- Org-level に 1 個だけ `JWT_PUBLIC` として置き、各 repo の cd.yml が好きな env 変数名にマップする方が Org Secret 一覧が肥大化しない
- repo 内のアプリコード (`config/initializers/authcore.rb`) が読む env 変数名は `AUTHCORE_JWT_PUBLIC_KEY` のままで OK。**翻訳は cd.yml が担当**
- 命名の一貫性 (`AUTHCORE_*` プレフィックス揃え) より、Org-shared な値を short name で持つ方を優先した

### `AUTHCORE_EXPECTED_AUDIENCE` / `AUTHCORE_EXPECTED_ISSUER` を登録していない

- AuthCore の `cmd/server/main.go:58-64` で `iss="authcore"` / `aud="authcore"` が hardcode
- bank の `config/initializers/authcore.rb:27-32` のデフォルトも両方 `"authcore"`
- 値が一致するので登録不要。明示しても害はないが、ハッカソンでは省略

### bank 専用 client を作らずテスト client を流用する

- AuthCore は admin endpoint も seed CLI も migration も持たない → bank 用 client を作るには「Go CLI を新規 PR で追加」か「CT で psql 直 INSERT」のどちらかが必要
- ハッカソン期間内ではこのコストを払わない判断
- AuthCore 側に既に居る `OAuthTest` (`clientfortest` / `passwordfortest`) で疎通する
- ⚠️ secret が辞書語なのでブルートフォース耐性なし。本番運用ではこの client を必ず捨てる

### worker service / runbook / 旧デプロイ残骸の扱い

- Solid Queue worker は現状 Gemfile には居るが、本番で worker プロセスが立っていない可能性が高い。ただし送金/mint で Active Job を使っていないなら今は不要 → ハッカソンでは判断保留
- `docs/runbooks/deploy.md` 新規作成と CLAUDE.md の旧デプロイ → cd.yml 書き換えはハッカソンでは省略可。CLAUDE.md は実態と乖離している部分だけ最低限直す
- 旧デプロイ残骸ディレクトリが残っていても無害なので削除はしない（後日 docs-overhaul で除去予定）

### develop と main のズレ

- 直近の本番 CD run は 2026-04-28（PR #72）まで。PR #73〜#81（B1 / B2 / B3 / B5 関連の cd.yml 変更含む）は develop には居るが main には未 merge
- 本タスクの PR が develop に merge されただけでは本番に届かない。**release PR (`develop → main`) を流す手順がセット**
- これは B5 タスクの責務外だが、検証時に「main へ反映するまで」の動線を意識する必要あり
