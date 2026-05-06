# JWT 検証後に呼ばれ、external_user_id に対応する User を返す。
# 無ければ同一トランザクション内で User + Account(kind: "user") を作成する。
# 新規作成かどうかは戻り値の `previously_new_record?` で判定できる。
class UserProvisioner
  def self.call(external_user_id:, name: nil, public_key: nil)
    new(external_user_id: external_user_id, name: name, public_key: public_key).call
  end

  def initialize(external_user_id:, name:, public_key:)
    @external_user_id = external_user_id
    @name = name
    @public_key = public_key
  end

  def call
    existing_user = User.find_by(external_user_id: @external_user_id)
    return existing_user if existing_user

    create_user!
  end

  private

  def create_user!
    ApplicationRecord.transaction do
      User.create!(external_user_id: @external_user_id, name: @name, public_key: @public_key)
    end
  rescue ActiveRecord::RecordNotUnique
    # 並行リクエストで同一 sub の User が別トランザクションで先に作られたケース。
    # external_user_id 以外の unique 制約違反まで吸収しないよう、既存が見つからなければ再 raise する。
    User.find_by(external_user_id: @external_user_id) || raise
  end
end
