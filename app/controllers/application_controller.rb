class ApplicationController < ActionController::API
  include ErrorResponder
  include JwtAuthenticatable
end
