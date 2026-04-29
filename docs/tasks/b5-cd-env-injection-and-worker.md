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
4. CLAUDE.md の「Kamal でデプロイ」記述を実態に修正

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

## 実装ステップ

1. **GitHub Secrets / Variables 登録**:
   - Secret: `AUTHCORE_JWT_PUBLIC_KEY`（PEM、改行入り）/ `AUTHCORE_CLIENT_SECRET`
   - Variable: `AUTHCORE_BASE_URL` / `AUTHCORE_CLIENT_ID` / `AUTHCORE_EXPECTED_AUDIENCE`(=authcore) / `AUTHCORE_EXPECTED_ISSUER`(=authcore)
   - PEM 改行: `appleboy/ssh-action` で env 経由で渡すと改行が壊れるケースあり → **PEM を base64 で encode して GH Secret に保存し、SSH 越しに `echo $B64 | base64 -d > /tmp/jwt.pub` してからファイルマウント** が安全。あるいは host 側 `/etc/fuju-bank/secrets/.env` に手動配置で逃げる選択肢も runbook に書く。

2. **`cd.yml` 更新**:
   - `env:` と `appleboy/ssh-action` の `envs:` に AUTHCORE_* を追加（前項の base64 方式採用)。
   - script: `export AUTHCORE_*` を追加して docker compose に流す。

3. **`compose.prod.yml` 更新**:
   - `web` service の `environment:` に AUTHCORE_* を追加。
   - 必要なら `worker` service を追加: `command: bundle exec rake solid_queue:start`、同じ image を再利用。
   - Solid Cable は ActionCable adapter として `web` 内で動くので独立 service 不要。ただし初回 `solid_cable_messages` テーブル作成が必要なら一回限り migrate を runbook 化。

4. **runbook 作成** (`docs/runbooks/deploy.md`):
   - 通常デプロイ手順 (cd.yml が走る)
   - secrets ローテーション手順（`AUTHCORE_JWT_PUBLIC_KEY` 等を更新する流れ）
   - 初回 Solid Cable migrate コマンド
   - ロールバック手順 (`git revert` → cd.yml 再 trigger)

5. **CLAUDE.md 更新**:
   - 「デプロイ: Kamal」を「GitHub Actions cd.yml + docker compose on Proxmox CT (Tailscale + SSH)」に書き換え。
   - `.kamal/` ディレクトリの扱い（残骸として残しておく / 削除）を判断。

## 検証チェックリスト

- [ ] cd.yml の dry-run（`act` or push to feature branch）で AUTHCORE_* が渡る
- [ ] 本番 web コンテナで `printenv | grep AUTHCORE` が全部見える
- [ ] B1 / B2 を merge した直後に本番 boot が成功する
- [ ] `worker` コンテナがログ出力中
- [ ] `https://api.fujupay.app/up` が 200
- [ ] CLAUDE.md / runbook が現行と一致
