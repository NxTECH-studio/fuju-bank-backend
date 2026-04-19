# JWT 検証後に呼ばれ、external_user_id に対応する User を返す。
# 無ければ同一トランザクション内で User + Account(kind: "user") を作成する。
class UserProvisioner
  def self.call(external_user_id:)
    new(external_user_id: external_user_id).call
  end

  def initialize(external_user_id:)
    @external_user_id = external_user_id
  end

  def call
    User.find_by(external_user_id: @external_user_id) || create_user!
  end

  private

  def create_user!
    ApplicationRecord.transaction do
      User.create!(external_user_id: @external_user_id, name: nil)
    end
  rescue ActiveRecord::RecordNotUnique
    # 並行リクエストで同一 sub の User が別トランザクションで先に作られたケース。
    # external_user_id 以外の unique 制約違反まで吸収しないよう、既存が見つからなければ再 raise する。
    User.find_by(external_user_id: @external_user_id) || raise
  end
end
