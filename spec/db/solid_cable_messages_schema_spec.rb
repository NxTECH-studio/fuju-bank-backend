require "rails_helper"

RSpec.describe "solid_cable_messages テーブル" do # rubocop:disable RSpec/DescribeClass
  let!(:connection) { ActiveRecord::Base.connection }
  let!(:columns) { connection.columns("solid_cable_messages").index_by(&:name) }

  # cable.yml で `connects_to: { database: { writing: primary } }` としているため、
  # ActionCable は ActiveRecord のデフォルト接続（=primary）を使う。本 spec は
  # その既定接続にテーブルが存在することを担保する。
  it "ridgepole が適用するデフォルト接続 (primary) に存在する" do
    expect(connection.table_exists?("solid_cable_messages")).to be(true)
  end

  it "Solid Cable が要求する列を null 不可で持つ" do
    %w[channel payload created_at channel_hash].each do |name|
      expect(columns).to have_key(name)
      expect(columns.fetch(name).null).to be(false), "#{name} should be NOT NULL"
    end
  end

  it "channel / payload は binary、channel_hash は bigint で定義されている" do
    expect(columns.fetch("channel").type).to eq(:binary)
    expect(columns.fetch("payload").type).to eq(:binary)
    expect(columns.fetch("channel_hash").sql_type).to eq("bigint")
    expect(columns.fetch("created_at").type).to eq(:datetime)
  end

  it "channel / channel_hash / created_at に索引を持つ" do
    index_columns = connection.indexes("solid_cable_messages").map(&:columns)
    expect(index_columns).to include(["channel"])
    expect(index_columns).to include(["channel_hash"])
    expect(index_columns).to include(["created_at"])
  end
end
