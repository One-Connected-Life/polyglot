class CreateOauthHandoffs < ActiveRecord::Migration[8.1]
  # One-time, short-lived bridge tokens for the iOS OAuth handoff (App A).
  #
  # Google refuses OAuth inside an embedded WKWebView (Error 403
  # disallowed_useragent), so the native shell runs the flow in
  # ASWebAuthenticationSession (Safari). Safari's cookie jar is NOT the
  # WKWebView's jar, so the resulting OmniAuth session can't be reused directly.
  # Instead OmniAuth success mints a row here, the shell receives the token via
  # the `mynewwords://auth-complete?handoff=<token>` custom-scheme redirect, and
  # hands it back to the WKWebView at /ios/session_handoff?token=… which redeems
  # it (single-use) to set the real signed session cookie inside the WKWebView.
  #
  # This is deliberately NOT Session#api_token: that is a long-lived bearer
  # credential; this is a transient single-use bridge (different conceptual role).
  def change
    create_table :oauth_handoffs do |t|
      t.string     :token,        null: false
      t.references :user,         null: false, foreign_key: true
      t.datetime   :expires_at,   null: false
      t.datetime   :redeemed_at   # set on first (and only) redemption
      t.timestamps
    end
    add_index :oauth_handoffs, :token, unique: true
  end
end
