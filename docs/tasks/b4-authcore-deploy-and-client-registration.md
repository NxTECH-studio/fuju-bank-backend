# B4: AuthCore のデプロイと bank client 登録

## メタ情報

- **Phase**: 1
- **並行起動**: ✅ B1 / B2 / B3 と並列可能
- **依存**: なし（B5 と密接連携、PR は別でも OK）
- **同期点**: app A1 へ「`AUTHCORE_BASE_URL = https://authcore.fujupay.app` 確定」を通知

## 概要

AuthCore は `/Users/ryota/Documents/works/proj-fuju/fuju-system-authentication` に **既に実装済み**の Go サービス。本タスクは新規構築ではなく、(1) AuthCore 自体を本番にデプロイ、(2) AuthCore の `clients` テーブルに bank の client を登録、(3) JWT 公開鍵を bank に配布、(4) 疎通スクリプト整備。

## 背景・目的

- AuthCore README §9 Phase 0〜8 のロードマップ済 / API 仕様は `docs/api-summary.md` `docs/openapi.yaml` を参照。
- bank backend 側 `Authcore::IntrospectionClient` は RFC 7662 準拠で既に正しい。
- bank が `/v1/auth/introspect` を叩くには Basic Auth 用 client_id / client_secret が必要。AuthCore の `clients` テーブルに row を作る運用が要る。

## 影響範囲

- リポジトリ: `fuju-system-authentication`（デプロイ・seed） / `fuju-bank-backend`（ENV 投入は B5）
- 本番インフラ: Proxmox CT に AuthCore コンテナを追加
- ファイル:
  - `fuju-system-authentication/.env.example`（本番値の参考）
  - `fuju-system-authentication/docs/runbooks/deploy.md`（新規・実装中に作る）
  - `fuju-system-authentication/scripts/seed_client.go`（新規・bank の client 登録 CLI、なければ追加）
  - `fuju-bank-backend/script/check_authcore.rb`（新規）

## 実装ステップ

1. **AuthCore のデプロイ先決定**:
   - 案 A: bank と同じ Proxmox CT に並べる（`compose.prod.yml` に `authcore` service 追加）
   - 案 B: 別 CT を立てる（運用分離、推奨）
   - TLS 終端: ホスト reverse proxy で `https://authcore.fujupay.app` を AuthCore コンテナに forward

2. **JWT 鍵ペアの管理**:
   - 初期は AuthCore CT 内 `keys/` に `openssl genrsa` で配置（README §8.1 手順）。
   - 公開鍵 `keys/jwt.public.pem` の中身を bank の `AUTHCORE_JWT_PUBLIC_KEY` に同期する手順を runbook に明記。**鍵ローテーション時は B5 経由で本番 ENV 更新 → bank 再起動が必要**。
   - 将来 KMS 化するときの移行ポイントもメモ。

3. **bank の client 登録**:
   - AuthCore の `clients` テーブルへの seed CLI を確認。無ければ `cmd/seed_client/main.go` (or Rails-side `bin/rails authcore:seed_client`) を追加。
   - `client_id=fuju-bank-backend` で row を作り、`client_secret` を strong random 生成 → Argon2id ハッシュで保存。発行した平文 secret は **1 回だけ表示**して本番 secret manager（GitHub Secrets / Kamal secrets）に投入。
   - 平文を Slack / コミットに残さない。

4. **疎通スクリプト** (`fuju-bank-backend/script/check_authcore.rb`):
   - `register → login → introspect` を 1 コマンドで実行。
   - 環境変数で AUTHCORE_BASE_URL を切替できるように。
   - 終了コード 0/1 で判定。

5. **AuthCore CD**:
   - AuthCore リポジトリ側に GitHub Actions / docker compose ベースの CD を組む（bank の cd.yml と同じ Proxmox CT に SSH する仕組みを流用）。
   - 既に AuthCore 側に CI はあるが CD は別。AuthCore リポジトリの README §9 Phase 0 を参照しつつ追加。

## 検証チェックリスト

- [ ] `https://authcore.fujupay.app/v1/auth/register` がローカルから疎通する
- [ ] `script/check_authcore.rb` が緑
- [ ] AuthCore の `clients` テーブルに `fuju-bank-backend` が登録されている
- [ ] bank の `AUTHCORE_*` ENV を投入する手順が runbook にある（B5 と接続）
- [ ] `keys/jwt.public.pem` が bank の `AUTHCORE_JWT_PUBLIC_KEY` と一致する手順が runbook にある

## PR description テンプレート

```
## 同期通知
- AUTHCORE_BASE_URL: https://authcore.fujupay.app（確定）
- bank client_id: fuju-bank-backend（確定）
- 公開鍵 PEM: 別途 secret manager 経由で共有
→ B5 で cd.yml / compose.prod.yml に投入、app A1 の release 値を確定値に更新してください。
```
