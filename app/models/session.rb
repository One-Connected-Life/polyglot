class Session < ApplicationRecord
  belongs_to :user

  # Native (iOS) clients authenticate by bearer token instead of the signed
  # cookie. A Session created for the API gets a random api_token; web sessions
  # leave it nil. Authenticate via `Authorization: Bearer <api_token>`.
  def self.start_for_api!(user, user_agent: nil, ip_address: nil)
    create!(
      user:       user,
      user_agent: user_agent,
      ip_address: ip_address,
      api_token:  SecureRandom.urlsafe_base64(32)
    )
  end
end
