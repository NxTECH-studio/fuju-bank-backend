# テスト用の RSA キーペア。プロセスで 1 回だけ生成し、rails_helper が
# AUTHCORE_JWT_PUBLIC_KEY に対応する公開鍵を注入する。
module TestKeypair
  module_function

  def private_key
    @private_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def public_key_pem
    private_key.public_key.to_pem
  end
end
