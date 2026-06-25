class OauthHandoff < ApplicationRecord
  # One-time, short-lived bridge token for the iOS OAuth handoff (App A).
  # See the CreateOauthHandoffs migration for the why.
  belongs_to :user

  TTL = 2.minutes

  # Mint a fresh single-use token for the given user.
  def self.issue!(user)
    create!(
      user:       user,
      token:      SecureRandom.urlsafe_base64(32),
      expires_at: TTL.from_now
    )
  end

  # Atomically redeem a token: returns the user iff the token exists, is
  # unredeemed, and unexpired — and marks it redeemed in the same UPDATE so a
  # second concurrent request can't reuse it. Returns nil otherwise.
  def self.redeem!(token)
    return nil if token.blank?

    now = Time.current
    handoff = where(token: token, redeemed_at: nil)
                .where("expires_at > ?", now)
                .first
    return nil unless handoff

    # Single-use guard: only the request that flips redeemed_at from NULL wins.
    updated = where(id: handoff.id, redeemed_at: nil).update_all(redeemed_at: now)
    updated == 1 ? handoff.user : nil
  end

  # Housekeeping helper (not auto-scheduled): drop spent/expired rows.
  def self.sweep_stale!(older_than: 1.hour)
    where("expires_at < ? OR redeemed_at IS NOT NULL", older_than.ago).delete_all
  end
end
