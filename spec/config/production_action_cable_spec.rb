require "rails_helper"

# production.rb は test 環境では実際にロードされないため、ファイル本文から
# `config.action_cable.*` への代入式を抽出して、その値オブジェクト
# (Array<Regexp> / Boolean) に対して挙動ベースのアサーションを行う。
# 単なる文字列 regex マッチより、整形ゆらぎや hostname の typo に強い。
RSpec.describe "config/environments/production.rb (Action Cable)" do # rubocop:disable RSpec/DescribeClass
  let!(:source) { Rails.root.join("config/environments/production.rb").read }

  let!(:origins) do
    match = source.match(/config\.action_cable\.allowed_request_origins\s*=\s*(\[[^\]]+\])/m)
    raise "allowed_request_origins assignment must be present" if match.nil?

    eval(match[1]) # rubocop:disable Security/Eval -- evaluating our own source so the test reflects real Regexp behavior
  end

  it "allows the https://api.fujupay.app origin" do
    expect(origins).to be_an(Array)
    expect(origins).to include(satisfy { |re| re.is_a?(Regexp) && re.match?("https://api.fujupay.app") })
  end

  it "rejects look-alike subdomain attacks" do
    expect(origins).to all(be_a(Regexp))
    [
      "https://api.fujupay.app.evil.com",
      "https://evil-api.fujupay.app",
      "https://api-fujupay.app",
      "http://api.fujupay.app", # 平文 HTTP は force_ssl 配下でも許可しない
    ].each do |bad|
      expect(origins.any? { |re| re.match?(bad) }).to be(false), "#{bad} は拒否されるべき"
    end
  end

  it "disables request forgery protection so native clients without Origin can connect" do
    match = source.match(/config\.action_cable\.disable_request_forgery_protection\s*=\s*(true|false)\b/)
    expect(match).not_to be_nil, "disable_request_forgery_protection assignment must be present"
    expect(match[1]).to eq("true")
  end
end
