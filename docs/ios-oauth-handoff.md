# iOS OAuth handoff (App A — "Sign in with Google")

## The bug
In App A (the Hotwire Native iOS shell), tapping **Continue with Google** showed:

> Access blocked: … Error 403: disallowed_useragent

Google **refuses OAuth inside embedded webviews** (WKWebView). App A renders the
web app in a WKWebView, so the Google sign-in page loaded in-webview and Google
blocked it. Email/password was unaffected (no third-party UA policy).

## The fix — route OAuth out to Safari, bridge the session back
The OAuth flow runs in `ASWebAuthenticationSession` (Safari-backed, which Google
accepts), then a one-time token bridges the resulting session into the WKWebView's
cookie jar.

### End-to-end flow
1. **Login view, native only** — under the Hotwire Native UA (`native_app?` in
   `ApplicationHelper`, matches `Hotwire Native` / `Turbo Native`), the Google
   button renders as a **GET `<a href="/auth/google_oauth2">`** (a plain Turbo
   link, *no* `data-turbo:false`) instead of the web's POST `button_to`. Only a
   GET link produces a Hotwire visit proposal the shell can intercept; a POST
   form would submit inside the WKWebView and 403.
2. **Shell intercepts** — `OAuthCoordinator.isOAuthStartURL` matches
   `/auth/<provider>`; `AppTabBarController.handle(proposal:)` rejects the
   in-webview visit and calls `OAuthCoordinator.begin(...)`.
3. **ASWebAuth opens** `GET /ios/oauth_start?provider=google_oauth2&callback_scheme=mynewwords`
   in Safari. `IosOauthController#start` flags the (Safari-side) Rails session as
   a native handoff and renders an **auto-submitting CSRF-protected POST form** to
   `/auth/<provider>` — preserving `omniauth-rails_csrf_protection` (GET initiation
   stays disabled, no security hole).
4. **Google accepts** (real Safari UA) → OmniAuth callback → `SessionsController#omniauth`.
   Because the handoff flag is set, instead of the web cookie redirect it **mints a
   single-use `OauthHandoff` token** (2-min TTL) and redirects to
   `mynewwords://auth-complete?handoff=<token>`.
5. **Custom scheme → shell** — ASWebAuth hands the `mynewwords://` URL back to
   `OAuthCoordinator`, which routes the **WKWebView** to
   `GET /ios/session_handoff?token=<token>`.
6. **Session established** — `IosOauthController#handoff` redeems the token
   (atomic, single-use, expiry-checked) and `start_new_session_for` sets the real
   signed `session_id` cookie in `WKWebsiteDataStore.default()`. All tabs become
   authenticated.

Failure path: if OmniAuth fails mid-handoff, `omniauth_failure` redirects to
`mynewwords://auth-complete` (no token) so ASWebAuth closes cleanly instead of
dead-ending on an HTML page in Safari.

## Why a new `oauth_handoffs` table (not `Session#api_token`)
`Session#api_token` is a *long-lived bearer credential* for the JSON API.
A handoff token is a *transient single-use bridge*. Different conceptual role →
separate table. `OauthHandoff.redeem!` flips `redeemed_at` in a single guarded
`UPDATE` so a replay/concurrent request can't reuse it.

## Files
- Web: `config/routes.rb`, `app/controllers/ios_oauth_controller.rb`,
  `app/views/ios_oauth/start.html.erb`, `app/controllers/sessions_controller.rb`
  (`#omniauth` + `#omniauth_failure` handoff branches), `app/models/oauth_handoff.rb`,
  `db/migrate/*_create_oauth_handoffs.rb`, `app/helpers/application_helper.rb`
  (`native_app?`), `app/views/sessions/new.html.erb` (native link vs web button).
  Specs: `spec/requests/ios_oauth_spec.rb`, `spec/models/oauth_handoff_spec.rb`.
- iOS: `Polyglot/Auth/OAuthCoordinator.swift` (already implemented the shell side),
  `Polyglot/Navigation/AppTabBarController.swift#handle(proposal:)`,
  `project.yml` CFBundleURLTypes (`mynewwords` scheme already registered).

## Not verifiable without a device + Google login
The full chain across the ASWebAuth ⇄ custom-scheme ⇄ WKWebView boundaries needs
a real device and Google credentials. Specifically: that Google accepts the
Safari UA end-to-end; that the `mynewwords://` redirect is actually delivered to
`ASWebAuthenticationSession`'s completion handler (not swallowed); and that the
plain Turbo link reaches `handle(proposal:)` rather than navigating the WKWebView
directly. All code paths are unit/request-tested; the cross-process glue is not.
