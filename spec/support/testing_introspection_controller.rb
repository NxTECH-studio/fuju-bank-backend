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
