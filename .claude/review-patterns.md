# レビューパターン集

過去のPRレビューから抽出した、よくある指摘パターンと注意点です。
実装時・レビュー時に参照してください。

---

## コード設計・アーキテクチャ

### 重複ロジックの抽出
```ruby
# NG: 同じロジックが複数回出現
albums.where.not(category: excluded_categories).limit(10)
albums.where.not(category: excluded_categories).order(:created_at)

# OK: メソッドに抽出
def filtered_albums
  albums.where.not(category: excluded_categories)
end

filtered_albums.limit(10)
filtered_albums.order(:created_at)
```

### 計算結果の変数化
```ruby
# NG: 同じ計算が複数回
if order.total_price * 0.1 > 1000
  discount = order.total_price * 0.1
end

# OK: 変数化
tax = order.total_price * 0.1
if tax > 1000
  discount = tax
end
```

### enum の積極的な使用
マジックナンバーや文字列定数は enum 化する。
```ruby
# NG
if status == "pending"

# OK
if status.pending?
```

### includes より preload/eager_load
```ruby
# NG: includes は暗黙的に処理を分ける
Order.includes(:user, :items)

# OK: 明示的に指定
Order.preload(:user, :items)  # 別クエリ
Order.eager_load(:user, :items)  # JOIN
```

---

## 命名・引数

### 引数名は意図を明確に
```ruby
# NG: 曖昧な引数名
def calculate_fee(date)

# OK: 意図が明確
def calculate_fee(enrollment_date)  # 「加入日」を表す
```

### 既存メソッドの活用
Rails/Ruby の既存メソッドを活用する。
```ruby
# 例: all_day, beginning_of_day, end_of_day など
```

---

## ロジックの品質

### 後から気付けない上書きを避ける
```ruby
# NG: インスタンス変数を外部から上書き
@display_text = "特別な値"

# OK: メソッド内で制御
def display_text
  return "特別な値" if special_case?
  default_text
end
```

### 可読性を保つ
AIしか読めないような複雑なロジックは避け、人間が理解できる形に分解する。

### シンプルな条件式
```ruby
# NG: 複雑な条件をそのまま使う
is_cancellable: item.is_a?(SpecialItem) && item.detail.print_required?

# OK: 意図を明確にする変数
is_goods = item.is_a?(SpecialItem) && item.detail.print_required?
is_cancellable: is_goods || item.is_a?(PackageItem)
```

### unless を使わない
```ruby
# NG
unless condition
  do_something
end

# OK: if で反転
if !condition
  do_something
end
```

### 識別子は slug を使う
```ruby
# NG: name は重複する可能性がある
if tag.name == "家族写真"

# OK: slug は一意性が保証されている
if tag.slug == "family"
```
※ name を使う場合はコメントで理由を説明する

### 添え字判定を避ける
```ruby
# NG: 位置が変わると壊れる
items[1].name

# OK: find で確実に見つける
items.find { |item| item.type == "target" }&.name
```

### コメントで分岐理由を説明
```ruby
# NG: 理由がわからない分岐
if tag.name == "家族写真"
  "#{tag.name}の撮影"
else
  "#{tag.name}撮影"
end

# OK: 理由を説明
# family タグの name が「家族写真」のため、自然な文章になるよう分岐
if tag.name == "家族写真"
  "#{tag.name}の撮影"
else
  "#{tag.name}撮影"
end
```

---

## 共通化・DRY

### ロジックの共通化
```ruby
# 既存のバリデーションメソッドを利用するなど
# 同じバリデーションロジックを再実装しない
```

---

## テスト

### 必要なケースのカバー
- 正常系だけでなく、異常系・境界値もテスト

### Time.current を使うなら travel_to で固定
```ruby
# NG: 時刻が固定されていない
it "returns correct date" do
  expect(subject.deadline).to eq(Time.current + 7.days)
end

# OK: 時刻を固定
it "returns correct date" do
  travel_to Time.zone.local(2025, 10, 15, 10, 0, 0) do
    expect(subject.deadline).to eq(Time.zone.local(2025, 10, 22, 10, 0, 0))
  end
end
```

### テストで前提条件を明示する
```ruby
# NG: 前提条件が暗黙的
context "制限付きの場合" do
  it "photographer1 が優先される" do
    expect(result).to eq(photographer1)
  end
end

# OK: 前提条件を明示
context "制限付きの場合" do
  before do
    # 制限なしの状態では photographer2 が優先される
    expect(described_class.call(restricted: false)).to eq(photographer2)
  end

  it "photographer1 が photographer2 より優先される" do
    expect(described_class.call(restricted: true)).to eq(photographer1)
  end
end
```

### before アクションは describe 直下にまとめる
共通の setup は describe 直下の before にまとめて、各 context で重複しないようにする。

### レコード生成は let! を使用する
レコード生成のタイミングの把握が難しくなるため、宣言時に確実に生成される let! を使用する。
```ruby
# NG
let(:item) { create(:item) }

# OK
let!(:item) { create(:item) }
```

---

## セキュリティ・パフォーマンス

### N+1 クエリの回避
`preload` や `eager_load` を使用してN+1を防ぐ。

### joins_values の確認
既にJOINされているかを確認してから追加のJOINを行う。

### .length vs .count
```ruby
# NG: count は毎回SQLを発行
@reviews.count  # リスト内で使うと N+1

# OK: length はメモリ上のデータを使用
@reviews.length

# または: インスタンス変数にキャッシュ
@review_count = @reviews.count
```

---

## Ruby/Rails 固有

### redirect_to に直指定
```ruby
# NG: 冗長
redirect_to some_path(id: @record.id)

# OK: シンプル
redirect_to @record
```

### distinct は必要な場合のみ
```ruby
# NG: 意味がない distinct
User.where(active: true).distinct

# OK: 重複が発生する場合のみ
User.joins(:orders).distinct
```

### update! を使う
```ruby
# NG: 失敗が暗黙的に無視される
record.save
record.update(name: "new")

# OK: 失敗時に例外を発生させる
record.save!
record.update!(name: "new")
```

---

## チェックリスト

実装・レビュー時に以下を確認：

### コード設計
- [ ] 重複ロジックがないか（メソッド抽出・変数化）
- [ ] マジックナンバーを enum 化しているか
- [ ] `includes` ではなく `preload`/`eager_load` を使っているか
- [ ] unless を使っていないか（if で反転）
- [ ] スキーマ変更は Ridgepole（db/Schemafile）で行っているか

### 命名・可読性
- [ ] 引数名が意図を表しているか
- [ ] 識別子に slug を使っているか（name ではなく）
- [ ] 条件判定が直接的か
- [ ] コメントで分岐理由を説明しているか

### テスト
- [ ] テストが必要なケースをカバーしているか（正常系・異常系・境界値）
- [ ] Time.current を使う場合は travel_to で固定しているか
- [ ] 前提条件を明示しているか
- [ ] let! を使っているか（let ではなく）

### その他
- [ ] 共通化できる箇所がないか
- [ ] update!/save! を使っているか
- [ ] N+1 クエリがないか
