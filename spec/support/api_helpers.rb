# Helpers for /api/v1 request specs: mint a bearer-token session and build the
# Authorization header. Mirrors how a native client authenticates.
module ApiHelpers
  def api_token_for(user)
    Session.start_for_api!(user).api_token
  end

  def auth_headers(user)
    { "Authorization" => "Bearer #{api_token_for(user)}" }
  end

  def json
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
