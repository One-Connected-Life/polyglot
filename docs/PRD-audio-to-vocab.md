# PRD — Upload your own audio → vocabulary deck

**Issue:** #3 · **Status:** decisions resolved, ready to build · **Last updated:** 2026-06-21

## Resolved decisions
- **D1 — Transcription: self-hosted Whisper** (`whisper.cpp`). Audio never leaves
  infrastructure we control. No cloud STT provider, no `OPENAI_API_KEY`.
- **D2 — Discard original audio after transcription.** Privacy-minimal: no standing personal
  audio kept; the user drills the extracted words only. (No replay-the-doctor feature in v1.)
- **D3 / D4** still open: source-language detection (default to user's target for now) and
  file-size/length guardrails — settle during /plan.

## 1. Problem & thesis

Polyglot's core differentiator is practising words from *your own life*, not a generic
curated list. The most personal source of "words I actually need" is **audio I encounter
but don't fully understand** — a doctor's voicemail, a municipality recording, an overheard
conversation, a movie clip. Today the deck generator can only start from a typed topic.

This feature lets a user **upload that audio**, have it transcribed, and turn the real
vocabulary in it into a deck they can drill immediately.

## 2. User story

> As a language learner, I want to upload audio I'd like to understand — e.g. an official
> Dutch voicemail — so the app extracts the useful vocabulary and turns it into a deck I can
> practise.

## 3. The privacy rule (non-negotiable — this is also a project rule)

The motivating data is **official / medical Dutch voicemails = real personal data**, and the
Polyglot repo is **public on GitHub under AGPL**. Two hard rules follow:

1. **Real personal recordings are NEVER committed.** They live only in the gitignored
   `sample-audio/` folder (local dev/testing). Committed test fixtures must be synthetic or
   public-domain. Enforced in `.gitignore` + memory rule
   `never_commit_real_personal_audio_or_sensitive_test_data`.
2. **Transcription provider is a privacy decision, not just a convenience one** — see §6. The
   default leans privacy-preserving (audio does not leave infrastructure we control) unless
   Mihai explicitly opts into a cloud provider.

## 4. Pipeline

Most of this already exists. The genuinely new stages are **upload** and **transcription**.

```
audio upload  →  transcribe (speech→text)  →  vocab extraction  →  review/edit  →  save deck  →  drill
   [NEW]            [NEW]                       [reuse DeckGenerator,    [NEW UI]      [exists]    [exists]
                                                 transcript instead
                                                 of topic]
```

- **Upload + storage:** ActiveStorage audio attachment on `Deck` (or a transient upload model).
  Stored under gitignored `storage/`.
- **Transcription:** new service (e.g. `Transcriber`) wrapping the chosen speech→text engine.
  Claude cannot transcribe audio, so this is a separate engine — see §6.
- **Vocab extraction:** generalize `DeckGenerator` so its prompt can take a **transcript** as
  the source material ("extract the useful vocabulary from this text") instead of a topic
  string. Reuses the existing Anthropic key, `Term`/`Translation` persistence, and the
  etymology/mnemonic/IPA enrichment already in the prompt.
- **Review:** new UI step — user prunes/edits candidate words before the deck is saved as
  `ready`. (Today decks go straight to `ready`; audio decks pass through a `review` state.)

## 5. Scope

### v1 (must-have)
- Signed-in user uploads an audio file from the decks/drill area.
- Audio is transcribed; a candidate word list is produced via the extraction prompt.
- User reviews/edits/prunes candidates and saves them as a named deck.
- New deck is immediately practisable in the existing drill.
- Privacy decision (§6) implemented and documented in README.
- Feature spec walks the full upload → review → save → practise journey.

### v1 open scope question
- **Retain original audio or discard after transcription?** Keeping it lets the user replay
  the doctor's actual sentence next to the extracted words (high value, more storage + more
  standing personal data). Discarding is the privacy-minimal default. → decide in §6 batch.

### Out of scope (v1)
- Real-time / streaming transcription.
- Speaker diarization.
- Multi-file batch upload.
- Mobile native capture (web upload only for v1).

## 6. Open decisions (resolve before building)

- [x] **D1 — Transcription provider → self-hosted `whisper.cpp`.** Audio stays on our box.
- [x] **D2 — Retain original audio → discard after transcription.** Privacy-minimal.
- [ ] **D3 — Source-language detection** vs assume the user's configured target language.
- [ ] **D4 — File-size / length limits + transcription cost/time guardrails.**

## 7. Acceptance criteria (grows during /plan)
- [ ] A signed-in user can upload an audio file from the drill/decks area.
- [ ] The audio is transcribed and a candidate word list is produced.
- [ ] The user can review/edit the candidate words and save them as a named deck.
- [ ] The new deck is immediately practisable in the existing drill.
- [ ] Privacy decision (D1) implemented and documented in README.
- [ ] Feature spec walks the full upload → deck → practice journey.
- [ ] No real personal audio is ever committed (fixtures synthetic/public-domain).

## 8. Test data

Four real official Dutch voicemails live in gitignored `sample-audio/` (local only). They are
the manual-test corpus for D1/D2 and the end-to-end journey — never committed.

## 9. Prior art

Background research pass (issue #3) checks whether an open-source project already does the
"ambient audio → vocab" loop, so we learn from / contribute to it rather than rebuild.
Findings land in issue #3.
