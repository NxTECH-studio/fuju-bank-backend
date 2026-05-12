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
    return user unless @public_id.present? && user.public_id != @public_id

    user.update!(public_id: @public_id)
    user
  rescue ActiveRecord::RecordInvalid => e
    # uniqueness 衝突: 別ユーザーが先に同じ public_id を取得済み（AuthCore 側でリネーム競合）。
    # bank.users.public_id は当面キャッシュ扱い (users-search-cross-service-identity.md) なので
    # 同期を諦め、bank の既存値のまま返す。次回同期 or AuthCore リネームで自然解消する想定。
    # update! 失敗時に in-memory の attribute が dirty なまま残るので reload で巻き戻す。
    raise unless e.record.errors.of_kind?(:public_id, :taken)

    user.reload
  rescue ActiveRecord::RecordNotUnique
    # SELECT-then-INSERT のレース時に DB ユニーク制約で弾かれるケース。同じ理由で同期を諦める。
    user.reload
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
