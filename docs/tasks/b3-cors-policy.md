# B3: CORS 方針決定と適用

## メタ情報

- **Phase**: 0
- **並行起動**: ✅ B1 / B2 と完全並列可能
- **依存**: なし
- **同期点**: なし（決定事項を CLAUDE.md / runbook に書く）

## 概要

`config/initializers/cors.rb` が初期 scaffold のフルコメントアウト状態。「ネイティブのみだから不要」「Web から叩く可能性あり」を明示的に決めて適用する。

## 背景・目的

- ネイティブクライアントは Origin ヘッダが空 / 非 Web オリジンなので CORS の影響を受けない。
- 一方で SNS 層 / マイニング層 / 管理 UI が将来ブラウザから叩く可能性は読めない。「不要」と決めて初期化子を削除するか、「許可オリジンを明示」して有効化するかを決める。

## 影響範囲

- ファイル:
  - `config/initializers/cors.rb`
  - `Gemfile`（`rack-cors` を削除する場合）
  - `Gemfile.lock`
  - `CLAUDE.md`（決定事項を反映）
- 破壊的変更: ブラウザクライアントが既に叩いていたら影響あり（現状は無し）

## 実装ステップ

1. **判断**:
   - **(a) ネイティブのみ前提** → `cors.rb` を「ネイティブクライアントのみ運用のため CORS 設定不要」のコメント 1 行に置き換え、`rack-cors` Gem は削除（依存を減らす）。
   - **(b) ブラウザ許可** → `https://fujupay.app` / `https://*.fujupay.app` のみ許可する初期化子を有効化。`Authorization` / `Content-Type` ヘッダ許可、`credentials: true` は cookie を扱わないので false で OK。
2. **採用案を実装**:
   - (a) の場合: `cors.rb` を 1 行コメントに、`Gemfile` から `gem "rack-cors"` を削除（無ければスキップ）、`bundle install`。
   - (b) の場合: `Rails.application.config.middleware.insert_before 0, Rack::Cors do ... end` を有効化。
3. **CLAUDE.md 更新**: 「アーキテクチャ」セクションに CORS 方針を追記。
4. **spec**: ブラウザ許可なら `spec/requests/cors_spec.rb` で OPTIONS preflight を確認。

## 検証チェックリスト

- [ ] `bundle exec rspec`
- [ ] (a) なら `Gemfile` に `rack-cors` が無いこと
- [ ] (b) なら `curl -X OPTIONS -H 'Origin: https://fujupay.app' ...` で適切な ACAO/ACAM が返る
- [ ] CLAUDE.md に決定が反映されている
