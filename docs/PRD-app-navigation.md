# PRD — App navigation (5-tab bar)

**Status:** Phase 1 (web) shipped · **Last updated:** 2026-06-25

The app renders inside a thin Hotwire Native iOS shell. The approved navigation is a
**5-tab bar** with a raised center Drill CTA:

```
My Words · Translate · 🔵 Drill (center CTA) · Add · Settings
```

The clickable prototype lives at `/design/app` (`app/views/design/app.html.erb`) and stays
in place as reference. Every page is **mobile-first**; drill-downs are plain links (the
shell turns them into native pushes); sub-slices are segmented pill toggles.

## Tab → URL contract (the iOS tab bar wires to these)

| Tab | URL | Notes |
|---|---|---|
| My Words | `/stats` | Segmented All · Learning · Retired; tap a word → `/terms/:id` |
| Translate | `/translate` (GET) | Type/Photo toggle; Save appends to the "Translated" deck |
| **Drill** | **`/play`** (bare) | Center CTA — launches straight into an all-words drill |
| Add | `/add` | Launcher → Generate a deck / From audio |
| Settings | `/onboarding` | Existing settings destination |

## Resolved decisions

- **D1 — Drill is "straight in."** The center CTA points at bare `/play` (no params), which
  `DrillsController#play` resolves to an **all-words drill**, source→target, with FSRS
  ordering. There is **no intermediate ready/home screen**. Practice is always available
  (FSRS orders/retires, never gates), so this URL always has cards. (Mihai: "straight in.")

- **D2 — Translate Save → the "Translated" deck.** Every saved translation is appended to a
  single per-user default deck named **"Translated"** (`User#translated_deck`, slug
  `translated`, auto-created on first save). It's the only Translate destination for now.
  Batches of 10+ route through the existing review screen first (prune-before-drillable);
  ≤9 land drillable immediately. (Previously Translate captured into "My Words"; the nav
  rework split it onto its own tab + deck.)

- **D3 — Branding cleanup on the drill home.** The drill home (`drills/home.html.erb`) no
  longer overrides `<title>` (falls back to the layout default "Polyglot") and drops the
  redundant `<h1>… drill</h1>` + subtitle, so the top is just the brand lockup. The brand
  **name** text ("Polyglot") is unchanged — the product name is still an open decision.

## What was reused vs new (web, Phase 1)

- **Drill** — reused `DrillsController#play` + bare `/play`. No code change; just confirmed
  the URL starts an all-words session with no params.
- **My Words** — reused `/stats`; added an All · Learning · Retired segmented filter
  (`?seg=`). Word → detail reuses the existing `/terms/:id` page.
- **Translate** — reused `Translator` / `ImageReader` / `Deck#absorb`. Added a GET landing
  page (`translate#new`, Type/Photo toggle) and pointed Save at the new `translated_deck`.
- **Add** — new `PagesController#add` hub linking to `/decks/new` and `/audio_decks/new`.
  "Paste a list" was in the prototype but **no such feature exists** yet, so it's omitted.
- **Settings** — unchanged (`/onboarding`).
