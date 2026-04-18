# frozen_string_literal: true

# system_issuance 口座 seed（idempotent）
#
# 使い方: bin/rails runner db/seeds/system_accounts.rb
#
# 発行の借方となる system_issuance 口座は初期化時に必ず存在する必要があるため、
# Account モデル実装後（#09）に本スクリプトを実行する。

system_account = Account.find_or_create_by!(kind: "system_issuance", user_id: nil)
puts "system_issuance account: id=#{system_account.id}, balance=#{system_account.balance_fuju}" # rubocop:disable Rails/Output
