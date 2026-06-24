# Polyglot — Brand

> Working brand for the language-learning app currently live at **mynewwords.org**.
> Marketing name "Polyglot" is the loose intent (not final); the technical bundle id
> stays `org.mynewwords.app`. Logo direction chosen 2026-06-24.

## The mark — "The Weave"

Three strands **braiding over and under** each other. It literally pictures the product's
signature feature — the **multi-language weave**, drilling several target languages at
once — and also reads as connection, interlacing, and steady growth. Confident at icon
size (the silhouette holds down to 29px), calm, a little playful.

**Assets** (`branding/assets/`):
- `polyglot-icon.svg` — the app-icon mark (1024×1024 rounded-square field).
- `polyglot-lockup.svg` — mark + "Polyglot" wordmark, for web headers / horizontal use.
- `logo-exploration-A-D.png` — the four concepts explored before landing on this one (C).

## Palette

| Role | Name | Hex |
|---|---|---|
| Primary / base (icon field, headers, ink) | **Indigo** | `#2D2A6E` |
| Accent / warmth (CTAs, highlights, the "correct" beat) | **Coral** | `#FF6F61` |
| Secondary / fresh (supporting strand, subtle fills) | **Sky** | `#36C5C0` |
| Neutral background | Paper | `#FBF7F0` |
| Neutral text | near-black | `#1F2A44` |

**Usage:** Indigo is the brand base. Coral is the single warm accent — use it sparingly
for the thing you want noticed (a button, a streak, a "you got it"). Sky is a supporting
tone, not a third loud color. Keep **2–3 colors per surface**; never all three shouting.

## Typography

Clean geometric / humanist sans. On Apple platforms that's the **system font**
(`-apple-system`, SF); on web a system stack with an Inter-style fallback. The wordmark
"Polyglot" is set in the same family — no separate display face needed.

## Voice & tone

Smart but warm. Calm, encouraging, lightly playful. **Not** corporate/sterile, **not**
childish. We celebrate small wins quietly (a word retired, a streak held), never with
confetti-screaming.

## Applying it

- **iOS app icon:** 1024 master from `polyglot-icon.svg` → Xcode AppIcon (single-size is
  enough on modern Xcode). Dark/tinted variants are **optional** (iOS 18+) and not
  required to ship — add later if wanted.
- **AccentColor (iOS):** Coral `#FF6F61` (or Indigo, depending on surface) so native
  controls/tints match the brand.
- **Web:** favicon derived from `polyglot-icon.svg`; brand colors as CSS variables; the
  lockup in the header. Keep the app's calm reading surfaces — brand accents, not a repaint.

## Open / not-yet-decided

- Final **marketing name** (Polyglot vs other) — decide before any public App Store
  submission. Bundle id is neutral (`org.mynewwords.app`) so this stays open.
- The mark may still be **refined** (stroke weight, strand spacing) — this is the chosen
  *direction*, not necessarily the final pixel.
- Eventual home: this `branding/` folder is built to relocate cleanly into a parent
  `polyglot/branding/` if/when we restructure (web / ios-hotwire / ios-native + branding).
