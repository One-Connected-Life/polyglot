class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_onboarding

  helper_method :current_user

  private

  def current_user
    Current.user
  end

  # Logged-in but hasn't picked a language yet → send to onboarding.
  def require_onboarding
    return unless authenticated?
    return if current_user.onboarded?
    return if %w[onboarding sessions registrations passwords].include?(controller_name)

    redirect_to onboarding_path
  end
end
