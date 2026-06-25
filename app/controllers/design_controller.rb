class DesignController < ApplicationController
  # Throwaway design preview: render candidate iOS tab bars in the browser so we
  # can pick one WITHOUT cutting a native app build. Unauthenticated + onboarding-
  # exempt so it's openable on the phone with a tap.
  allow_unauthenticated_access only: :tabs
  skip_before_action :require_onboarding, only: :tabs

  def tabs
    render layout: false
  end
end
