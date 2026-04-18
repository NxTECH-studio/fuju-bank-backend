require "rails_helper"

RSpec.describe UserChannel, type: :channel do
  let!(:user) { create(:user) }

  it "subscribes with valid user_id" do
    subscribe(user_id: user.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end

  it "rejects subscription with unknown user_id" do
    subscribe(user_id: user.id + 1)
    expect(subscription).to be_rejected
  end
end
