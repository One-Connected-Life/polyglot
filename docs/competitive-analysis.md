# Competitive Feature Analysis — Custom / Polyglot / Audio Vocabulary Learning

*Research pass, June 2026. Every cell is source-cited or flagged UNVERIFIED.*

Axes: **(1)** custom typed words · **(2)** open languages + 3+ simultaneous · **(3)** arbitrary-audio→vocab · **(4)** SRS retires known words · **(5)** IPA/phonetic · **(6)** etymology/mnemonics · **(7)** privacy/self-host/OSS

## Feature matrix

| Product | 1. Custom words | 2. Open langs / 3+ simul | 3. Audio→vocab | 4. SRS retires | 5. IPA | 6. Etymology | 7. Privacy/OSS |
|---|---|---|---|---|---|---|---|
| Readlang | Yes, but hidden (manual add + click-extract) | ~119 langs / **No 3+** | **Yes** — own MP3 → Whisper → cards | No terminal state; intervals only lengthen | likely no | No | None; cloud only |
| LingQ | Yes (manual "Add a Term" + click) | Fixed 50+ / **No 3+** | **Yes** — Whisper transcribes own MP3 | **Yes** — "Known" words never reviewed (silent) | No | No | None; cloud |
| Language Reactor | Click-to-save only; typed entry UNVERIFIED | 40+, subtitle-bound / **No 3+** | **No** — needs existing subtitles | No real internal SRS; exports to Anki | Transliteration; IPA UNVERIFIED | No | Closed cloud extension |
| Migaku | Mining from media; manual-type UNVERIFIED | Fixed 11 / **No 3+** | **Yes (Apr 2026)** — server-side AI Subtitles; arbitrary local file UNVERIFIED, Early Access | Known-word-aware; algo unnamed | Strong: pitch accent, furigana, pinyin | No | Proprietary cloud |
| VoiceLingua | All user-supplied via audio; typed UNVERIFIED | ~8 fixed (UNVERIFIED) / **No 3+** | **Yes — core**; Android floating-mic overlay | SM-2; retire UNVERIFIED | UNVERIFIED | UNVERIFIED | **UNVERIFIED** |
| Glossika | **No** — closed sentence library | ~65 fixed; base lang removable / no 3+ | **No** — you record yourself | Tapers via intervals; no celebrate | **Yes — IPA + romanization everywhere** | No (anti-explanation) | None; cloud |
| Anki | **Yes — foundational**, user-authored notes | **Agnostic; ONE note CAN show 3+ langs** via fields | Natively no; add-ons are TTS/subtitle-mining | No delete; long intervals + suspend/bury; SM-2→FSRS | Via field/add-on (anki-ipa) | Via fields/shared decks | **Yes — OSS (AGPL/GPL), local-first** |
| Clozemaster | Yes, Pro (manual + CSV + auto) | 50+ langs, **strictly pairwise** / **No 3+** | **No** — own TTS only | Mastery steps → 180d loop; algo unnamed | Largely no | No | Proprietary cloud |
| AnkiDecks | Yes (upload own lecture/podcast) | 50+, one→one / **No 3+** | **Yes** — ASR → concept-extract → cards | Built-in FSRS; no retire-known | No | Images only | Proprietary cloud |
| AnkiForge | Yes (word list/text/PDF — no audio in) | Open set / no 3+ | **No** (TTS out only) | Delegates to Anki | **Yes — per-word IPA** | Example sentences + AI image | OSS (GPL-3.0) add-on, cloud generation |
| asbplayer (+Whisper) | Yes (local files / streaming subs) | Agnostic; dual subtitles / no 3+ | Via 2-tool Whisper seam | None of its own (→ Anki) | No native | None | **MIT, fully local, offline** |

## Per-axis synthesis

1. **Custom typed words** — Best: Anki (whole model is user-authored notes). Treat an arbitrary word+translation as a first-class object, not a byproduct of imported content.
2. **Open languages + 3+ simultaneous** — Best: Anki, and only Anki (manual template). Every purpose-built app is strictly bilingual per concept. **Single largest whitespace in the field.** Model the *concept* as the entity, languages as fields.
3. **Audio→vocab** — Best: VoiceLingua (arbitrary mic capture) and Migaku (AI Subtitles, Early Access). Readlang and LingQ both do MP3→Whisper→cards, so **audio-from-a-file is table stakes among leaders, not a differentiator.** Whisper is the universal engine; differentiation is capture UX + one-product seamlessness.
4. **SRS that retires known words** — Best: LingQ ("Known" never resurfaced) and Anki (long intervals + suspend/bury). **Nobody celebrates mastery** — the "drop it AND mark the moment" behavior is unoccupied. Build on FSRS (modern default), not bespoke SM-2.
5. **IPA / phonetic** — Best: Glossika (IPA + romanization, toggleable). Adopt the IPA/romanized/native-script toggle.
6. **Etymology / mnemonics** — Best: nobody. **Absent across the entire field.** Clean whitespace.
7. **Privacy / self-host / OSS** — Best: Anki (OSS, local-first) and asbplayer (MIT, fully local). Every commercial purpose-built app is closed cloud. **No product combines native audio-transcription AND full local/open-source** — that intersection is empty.

## Where mynewwords can be best

Three candidate differentiators, least served by incumbents:

1. **One concept across 3+ languages simultaneously (axis 2)** — strongest whitespace. Zero purpose-built apps; only Anki, manually. Our `Translation` model already implements concept-as-entity / languages-as-fields.
2. **Retire-and-celebrate mastery (axis 4)** — the "Duolingo problem" is unaddressed *as an experience*. Cheap on FSRS; emotionally differentiated.
3. **Etymology / memory hints (axis 6)** — absent field-wide; low-cost with an LLM.

Conditional fourth — **privacy/self-host (axis 7)** — real gap (no commercial app offers it) but only an edge with self-hosted Whisper AND open-source. Cloud STT gives no edge.

**Learn rather than reinvent:** audio→vocab (table stakes, match with Whisper), IPA (copy Glossika's toggle), FSRS (the engine the leaders standardized on — build retire-and-celebrate on top of it).

**Flagged unknowns:** VoiceLingua privacy/pricing/IPA/lang-count (single cached source, site 403s); Migaku exact SRS algo + arbitrary-local-audio support (Early Access); Anki FSRS-as-default; Clozemaster SRS algo/pricing; Language Reactor IPA + manual entry; whether any product *hard-retires* vs just stretches intervals.
