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
end
