class AddApiTokenToSessions < ActiveRecord::Migration[8.1]
  def change
    # Bearer token for native-client (iOS) API auth. The web flow keeps using the
    # signed cookie; native clients get a Session row with a random api_token and
    # send it as `Authorization: Bearer <token>`. nil for cookie-only web sessions.
    add_column :sessions, :api_token, :string
    add_index  :sessions, :api_token, unique: true
  end
end
