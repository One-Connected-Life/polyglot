# Polyglot — project instructions

A custom-vocabulary drill with an FSRS spaced-repetition engine behind a UI a human
enjoys: AI-generated decks, IPA, etymology, a multi-language weave, and audio→vocab
(upload a recording, get a deck). Mihai's **solo** project. Repo:
`One-Connected-Life/polyglot`. Lives under `~/coding/ocl/` but is its own repo.

## Ship fast — build then DEPLOY immediately (no asking)

This is a solo repo and Mihai wants what you build usable on his phone fast. **Once a
feature builds and its tests pass, deploy it** — don't stop to ask for permission.

- Deploy is **manual**: `rake deploy` (Kamal; reads `KAMAL_REGISTRY_PASSWORD` from `.env`).
  Pushing to `main` only runs CI (`.github/workflows/ci.yml`) — it does **not** auto-deploy.
  So actually run the deploy; don't assume a push shipped it.
- The only bar is **green, not broken**: deploy working code, never something that 500s.
  "Don't ship breakage" is correctness, not hesitation.
- Commit and push freely too — never gate those on permission here.

(Origin: "please deploy as soon as you build stuff! why are you holding back?" — memory
`polyglot_build_then_deploy_immediately`.)

## Stack
- Rails 8.1, Ruby 3.4, SQLite, Hotwire (Turbo + Stimulus), importmap, Tailwind v4, RSpec.
- AI deck generation via the Anthropic Messages API (`ANTHROPIC_API_KEY`), `Net::HTTP`, no gem.
- Jobs: dev uses the **`:async`** adapter (in-process, no worker needed); Solid Queue only
  runs in Puma when `SOLID_QUEUE_IN_PUMA=1` **and** its tables are migrated.
- Deployed with Kamal to **mynewwords.org**.

## Audio → vocab (issue 3)
Self-hosted transcription: `ffmpeg` (normalize to 16kHz WAV) → `whisper.cpp` (`whisper-cli`)
→ extract vocab with `DeckGenerator(transcript:)`. See `docs/PRD-audio-to-vocab.md`.
- **Privacy is load-bearing:** the motivating input is medical/official voicemails. Audio is
  transcribed on our own box and **deleted after** (never persisted). Real personal recordings
  live only in gitignored `sample-audio/` and are **never committed** (repo is public AGPL) —
  memory `never_commit_real_personal_audio_or_sensitive_test_data`.
- **Prod needs `ffmpeg` + `whisper.cpp` + a model in the Docker image** — without them, prod
  can't transcribe. (Local dev uses the Homebrew `whisper-cli` + `~/.local/share/whisper-models`.)
  Override paths via `WHISPER_CLI` / `WHISPER_MODEL` / `FFMPEG_BIN` env.

## Product invariant
Practice is **always available** — never "no words due." FSRS orders/retires, never gates.
(memory `language_app_practice_always_available`)
