require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let!(:sub) { "01HYZ0000000000000000000AA" }

  def subprotocol_headers(token)
    { "Sec-WebSocket-Protocol" => "actioncable-v1-json, bearer, #{token}" }
  end

  describe "subprotocol で JWT を渡したとき" do
    it "有効な access token で接続が確立し current_user に external_user_id が乗る" do
      token = issue_test_jwt(sub: sub)

      connect "/cable", headers: subprotocol_headers(token)

      expect(connection.current_user.external_user_id).to eq(sub)
    end

    it "新規 sub の場合は User を lazy provision する" do
      token = issue_test_jwt(sub: sub)

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to change { User.count }.by(1)
    end

    it "既存 User があれば再利用する" do
      existing = create(:user, external_user_id: sub)
      token = issue_test_jwt(sub: sub)

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.not_to(change { User.count })

      expect(connection.current_user).to eq(existing)
    end
  end

  describe "Authorization ヘッダ fallback" do
    it "Bearer ヘッダで接続が確立する" do
      token = issue_test_jwt(sub: sub)

      connect "/cable", headers: { "Authorization" => "Bearer #{token}" }

      expect(connection.current_user.external_user_id).to eq(sub)
    end
  end

  describe "reject 条件" do
    it "JWT がない場合は reject する" do
      expect { connect "/cable" }.to have_rejected_connection
    end

    it "subprotocol に bearer がない場合は reject する" do
      expect do
        connect "/cable", headers: { "Sec-WebSocket-Protocol" => "actioncable-v1-json" }
      end.to have_rejected_connection
    end

    it "subprotocol の bearer の後にトークンがない場合は reject する" do
      expect do
        connect "/cable", headers: { "Sec-WebSocket-Protocol" => "actioncable-v1-json, bearer" }
      end.to have_rejected_connection
    end

    it "type=refresh の JWT は reject する" do
      token = issue_test_jwt(sub: sub, type: "refresh")

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to have_rejected_connection
    end

    it "exp が過去の JWT は reject する" do
      token = issue_test_jwt(sub: sub, exp: 1.minute.ago)

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to have_rejected_connection
    end

    it "別の鍵で署名された JWT は reject する" do
      other_key = OpenSSL::PKey::RSA.new(2048)
      token = issue_test_jwt(sub: sub, key: other_key)

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to have_rejected_connection
    end

    it "aud 不一致の JWT は reject する" do
      token = issue_test_jwt(sub: sub, aud: "other")

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to have_rejected_connection
    end

    it "iss 不一致の JWT は reject する" do
      token = issue_test_jwt(sub: sub, iss: "other")

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to have_rejected_connection
    end

    it "sub クレームが欠落した JWT は reject する" do
      payload = { type: "access", aud: "authcore", iss: "authcore", exp: 5.minutes.from_now.to_i }
      token = JWT.encode(payload, test_private_key, "RS256")

      expect do
        connect "/cable", headers: subprotocol_headers(token)
      end.to have_rejected_connection
    end
  end
end
