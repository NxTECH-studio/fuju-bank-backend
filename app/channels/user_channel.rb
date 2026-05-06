# User 単位のリアルタイム配信チャネル。
# `ApplicationCable::Connection` が確立した `current_user` の broadcast のみを stream する。
# 他人の channel を購読する経路は構造的に存在しない。
class UserChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end

  def unsubscribed; end
end
