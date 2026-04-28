class ApplicationController < ActionController::API
  include ErrorResponder
  include JwtAuthenticatable

  private

  # 現リクエストの JWT sub に対応する User を返す。未プロビジョン時は nil。
  # lazy provisioning は POST /users/me 限定で UsersController が UserProvisioner を直接呼ぶ。
  # それ以外のエンドポイントで未存在の場合は呼び出し側で 401 UNAUTHENTICATED を返すこと。
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(external_user_id: current_external_user_id)
  end
end
