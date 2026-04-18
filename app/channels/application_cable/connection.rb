# TODO: 認証は将来拡張（public_key 署名検証）
class ApplicationCable::Connection < ActionCable::Connection::Base
  # MVP: 認証は UserChannel#subscribed 内で user_id を検証する簡易方式
end
