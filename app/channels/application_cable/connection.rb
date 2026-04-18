# ActionCable の基底 Connection。
# MVP では識別子を用いず、UserChannel#subscribed 内で user_id を検証する簡易方式を採る。
# TODO: 認証は将来拡張（HUD の public_key 署名検証）
class ApplicationCable::Connection < ActionCable::Connection::Base
end
