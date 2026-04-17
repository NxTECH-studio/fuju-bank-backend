class BankError < StandardError
  def initialize(code:, message:, http_status: 422)
    super(message)
    @code = code
    @http_status = http_status
  end

  attr_reader :code, :http_status
end
