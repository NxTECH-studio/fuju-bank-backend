# 複合 expect (`.to change(...).and not_change(...)`) を書けるように
# `not_change` を `change` の否定として定義する。これがないと
# `change { X }.by(0)` を多用することになり RuboCop の RSpec/ChangeByZero
# が連発する。
RSpec::Matchers.define_negated_matcher :not_change, :change
