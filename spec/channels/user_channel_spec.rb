require "rails_helper"

RSpec.describe UserChannel, type: :channel do
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }

  before do
    stub_connection(current_user: user)
  end

  it "current_user の broadcast を stream する" do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end

  it "他人の broadcast を stream しない" do
    subscribe

    expect(subscription).not_to have_stream_for(other_user)
  end
end
