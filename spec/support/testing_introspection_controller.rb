class TestingIntrospectionController < ApplicationController
  include IntrospectionRequired

  def show
    render(
      json: {
        external_user_id: current_external_user_id,
        introspection_sub: introspection_result.sub,
      },
      status: :ok,
    )
  end
end

class TestingMfaController < ApplicationController
  include IntrospectionRequired
  include MfaRequired

  def show
    render(json: { ok: true }, status: :ok)
  end
end
