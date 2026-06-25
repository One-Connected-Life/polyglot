module ApplicationHelper
  # Shared input styling — distinct bg, border, padding, dark variants (ux-primer:
  # "an input must read as an input"). Hints/placeholders muted vs entered text.
  def field_classes
    "w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-base sm:text-sm outline-none " \
      "focus:border-brand-indigo focus:ring-2 focus:ring-brand-indigo/20 " \
      "dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 " \
      "dark:placeholder-gray-500 dark:focus:border-brand-sky dark:focus:ring-brand-sky/20"
  end

  def primary_button_classes
    "w-full rounded-lg bg-brand-indigo px-4 py-2 text-sm font-medium text-white shadow-sm " \
      "hover:bg-brand-indigo/90 dark:bg-brand-indigo dark:text-white dark:hover:bg-brand-indigo/80"
  end

  # [name, code] pairs for language <select>s.
  def language_options
    Translation::LANGUAGES.map { |code, name| [name, code] }
  end

  # True when the FSRS scheduling path is live (FSRS_ENABLED=1). FSRS supersedes
  # a couple of legacy drill toggles (skip_easy → auto-skips cognates; hide_mastered
  # → retires mastered words), so Settings greys those out with an explanation
  # rather than presenting dead controls. Mirrors DrillsController#fsrs_enabled?.
  def fsrs_enabled?
    ENV["FSRS_ENABLED"].to_s == "1"
  end

  # True when the page is rendered inside the Hotwire Native WKWebView (App A).
  # Hotwire Native stamps "Hotwire Native" / "Turbo Native" into the WKWebView's
  # User-Agent. We key off it so OAuth buttons render as GET links the native
  # shell can intercept (and divert to ASWebAuthenticationSession) rather than
  # in-webview POSTs to Google — which Google blocks (Error 403
  # disallowed_useragent). The ASWebAuth (Safari) request that hits
  # /ios/oauth_start does NOT carry this marker, which is correct: there we want
  # the normal CSRF-protected POST flow.
  def native_app?
    request.user_agent.to_s.match?(/Hotwire Native|Turbo Native/i)
  end

  # Build tag for the brand lockup so Mihai always knows which native build he's
  # on (e.g. "H8" = Hotwire shell, build 8). The native shell advertises itself
  # in the User-Agent with the token "OCL-App/H<CFBundleVersion>" (App A = "H";
  # App B native = "N" when it ever reports). Returns e.g. "H8" or nil for a
  # plain browser (no token). Contract is shared with polyglot-ios
  # WebViewConfiguration.swift — keep the token format identical on both sides.
  def app_build_tag
    m = request.user_agent.to_s.match(%r{OCL-App/([HN])(\d+)})
    return nil unless m

    "#{m[1]}#{m[2]}"
  end
end
