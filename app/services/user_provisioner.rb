# JWT 検証後に呼ばれ、external_user_id に対応する User を返す。
# 無ければ同一トランザクション内で User + Account(kind: "user") を作成する。
# 新規作成かどうかは戻り値の `previously_new_record?` で判定できる。
#
# 既存ユーザーの場合、`public_id` が非 nil なら既存値を上書きする。
# AuthCore -> bank の public_id 伝播経路がここしか無く、上書きしないと
# 検索 / directory 系が古い handle のままになるため。
class UserProvisioner
  def self.call(external_user_id:, name: nil, public_key: nil, public_id: nil)
    new(external_user_id: external_user_id, name: name, public_key: public_key, public_id: public_id).call
  end

  def initialize(external_user_id:, name:, public_key:, public_id:)
    @external_user_id = external_user_id
    @name = name
    @public_key = public_key
    @public_id = public_id
  end

  def call
    existing_user = User.find_by(external_user_id: @external_user_id)
    return sync_existing!(existing_user) if existing_user

    create_user!
  end

  private

  def sync_existing!(user)
    user.update!(public_id: @public_id) if @public_id.present? && user.public_id != @public_id
    user
  end

  def create_user!
    ApplicationRecord.transaction do
      User.create!(
        external_user_id: @external_user_id,
        name: @name,
        public_key: @public_key,
        public_id: @public_id,
      )
    end
  rescue ActiveRecord::RecordNotUnique
    # 並行リクエストで同一 sub の User が別トランザクションで先に作られたケース。
    # external_user_id 以外の unique 制約違反まで吸収しないよう、既存が見つからなければ再 raise する。
    User.find_by(external_user_id: @external_user_id) || raise
  end
end
