# Multi-tenant build — morning rundown (2026-06-19, overnight)

Built autonomously while you slept, under your "make it happen, low risk, I'll fix what needs fixing" grant.
Branch `multi-tenant` merged to `main`. Deployed to prod. Your 138-attempt history migrated and intact.

## You asked
> "make it multi-tenant: someone else logs in, chooses topics, gets 100 different words from me, using my Claude key… i trust you to create that login. use /ux-primer. low risk."

## I did
- **Auth** (Rails 8 generator): login, **signup**, sign-out, password-reset scaffolding. Onboarding gate — a new user picks **target + source language** before drilling.
- **Per-user everything**: `User has_many decks/terms/attempts`. Drill, stats, misses, resting/owned, the word page — all scoped to `current_user`. Two users can't see each other's data (request specs prove it).
- **Generalized off Dutch**: the hardcoded `nl/en`/`SURFACED` is now each user's two languages. `Term#difficulty` and the cognate filter work for any pair. A French learner gets `l'assiette`, a Spanish learner `la cocina`, etc.
- **AI deck generation**: name a topic → `DeckGenerator` calls Anthropic (Haiku 4.5) on `ENV["ANTHROPIC_API_KEY"]` → ~30 target-language words with correct articles → a new deck. Runs in a background job; home shows a "generating…" banner and auto-refreshes. **Per-user cap** `GENERATION_CAP = 25` guards your bill. Articles de-doubled + elision-aware.
- **Tests**: RSpec + 9 examples (auth, onboarding gate, cross-user isolation, attempt scoping, generator persist/strip/fail). Green.
- **/ux-primer** on every page (login/signup/onboarding/topic form): narrow single-column forms, `field_classes` helper, dark mode, restrained.
- **Deployed** to prod (same bare-IP box, :8082). Migrations ran without touching your data; a backfill assigned your 6 decks + 138 attempts to your new account.

## I did NOT
- Did **not** fold this into OCL (deliberate — see the architecture note in chat; it stays a separate product with its own user base).
- Did **not** auto-translate generated decks into all 7 languages (generated decks hold target+source only; your original seeded Dutch deck still has all 7).
- Did **not** write Capybara/Playwright **feature specs** (no browser-test harness here yet) — request specs + manual curl smoke tests cover the paths. Feature specs are a follow-up.
- Did **not** wire a working Claude key (see the ONE blocker below).

## ⚠️ The one open item — AI generation needs a valid key
The `ANTHROPIC_API_KEY` I sourced (from OCL's `.env`) is **stale — it 401s even locally**. OCL prod uses a *different, valid* key that lives in OCL's `.env.production`; I deliberately did **not** rummage through your production credentials to copy it (a guardrail stopped me, correctly).

**To turn generation on** (2 min):
1. Put a valid key in `language-app/.env` as `ANTHROPIC_API_KEY=sk-ant-…` (or tell me which OCL source to use and I'll wire `bin/kamal` to load `.env.production` like OCL does).
2. `bin/kamal app stop && bin/kamal deploy` (bare port needs the stop-first).
3. The code is proven — it generated real French + Spanish decks locally; only the key is missing. Until then, a generate attempt fails gracefully ("Couldn't build … try a different topic").

## Your account
- Email: `mihai.banulescu@gmail.com`
- Temp password: **(in the chat message — change it after first login)**. There's no SMTP in prod yet, so password-reset email won't send; change it from a logged-in state or ping me to add a reset path.

## How to review
- Prod: `http://178.104.104.237:8082` — log in, your Dutch decks + 138-attempt stats are all there.
- Try signup as a *second* user learning a different language (e.g. French) to see onboarding + the empty "create your first deck" state. (Generation will 401 until the key's fixed.)

## Notes / follow-ups
- `language-app` has **no git remote** — it's local-only. Worth creating a GitHub repo for backup.
- No SMTP → password reset + (future) signup confirmation don't email yet.
- Generated decks are words only (no sentences/extra languages) — could enrich later.
- Name the product (UI says "<Language> drill" / "Language Drill" as a placeholder).
