# db/seeds.rb は `bin/rails db:seed` から読まれるエントリポイント。
# 個別 seed は `db/seeds/` 配下に分割し、ここから一括 load する。
#
# 各 seed は `find_or_create_by!` 等で idempotent に書くこと
# （CD で deploy 毎に走る想定）。

Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |path| load path }
