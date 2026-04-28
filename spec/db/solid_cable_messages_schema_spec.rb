require "rails_helper"

RSpec.describe "solid_cable_messages テーブル" do # rubocop:disable RSpec/DescribeClass
  let!(:connection) { ActiveRecord::Base.connection }

  it "primary DB に存在する（Solid Cable 相乗り構成）" do
    expect(connection.table_exists?("solid_cable_messages")).to be(true)
  end

  it "Solid Cable が要求する列を持つ" do
    columns = connection.columns("solid_cable_messages").map(&:name)
    expect(columns).to include("channel", "payload", "created_at", "channel_hash")
  end

  it "channel / channel_hash / created_at に索引を持つ" do
    index_columns = connection.indexes("solid_cable_messages").map(&:columns)
    expect(index_columns).to include(["channel"])
    expect(index_columns).to include(["channel_hash"])
    expect(index_columns).to include(["created_at"])
  end
end
