# WebSocket 接続レイヤで AuthCore JWT を検証し、current_user を確立する。
#
# JWT 配送方式:
#   Sec-WebSocket-Protocol: actioncable-v1-json, bearer, <jwt>
# Rails 側は `actioncable-v1-json` のみを subprotocol として echo し、
# `bearer` / トークンは認証情報としてのみ消費する。
# クライアント実装が困難な環境向けに `Authorization: Bearer <jwt>` も受け付ける。
class ApplicationCable::Connection < ActionCable::Connection::Base
  identified_by :current_user

  def connect
    self.current_user = find_verified_user
  end

  private

  def find_verified_user
    token = extract_jwt
    claims = Authcore::JwtVerifier.call(token: token)
    UserProvisioner.call(external_user_id: claims.fetch("sub"))
  rescue AuthenticationError, KeyError
    reject_unauthorized_connection
  end

  def extract_jwt
    extract_from_subprotocol || extract_from_authorization_header
  end

  # `Sec-WebSocket-Protocol: actioncable-v1-json, bearer, <jwt>` から JWT を抽出する。
  # `bearer` トークンの直後の要素を JWT として扱う。
  def extract_from_subprotocol
    raw = request.headers["HTTP_SEC_WEBSOCKET_PROTOCOL"] || request.headers["Sec-WebSocket-Protocol"]
    return nil if raw.blank?

    parts = raw.split(",").map(&:strip)
    bearer_index = parts.index("bearer")
    return nil if bearer_index.nil?

    parts[bearer_index + 1].presence
  end

  def extract_from_authorization_header
    header = request.headers["Authorization"]
    return nil if header.blank?

    match = header.match(/\ABearer\s+(.+)\z/)
    match && match[1]
  end
end
