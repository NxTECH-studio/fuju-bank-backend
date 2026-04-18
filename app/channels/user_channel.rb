# User 単位のリアルタイム配信チャネル。
# 接続時に user_id を受け取り、該当 User の broadcast を stream する。
#
# TODO: 認証は将来拡張（HUD の public_key 署名検証）
class UserChannel < ApplicationCable::Channel
  def subscribed
    user = User.find_by(id: params[:user_id])
    if user.nil?
      reject
    else
      stream_for user
    end
  end

  def unsubscribed; end
end
