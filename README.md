# Polyglot

A custom-vocabulary drill that puts an Anki-grade spaced-repetition engine (FSRS)
behind a UI a human actually enjoys — with AI-generated decks, IPA, etymology, and
a multi-language weave. Make new words yours.

## License

Copyright (C) 2026 Mihai Banulescu.

Licensed under the **GNU Affero General Public License v3.0 or later** (AGPL-3.0-or-later).
See [`LICENSE`](LICENSE). The AGPL's network clause means anyone who runs a modified
version as a service must offer their source under the same terms — forks stay open,
improvements flow back. (Relicensed from MIT, 2026-06-21.)

The FSRS scheduler is used via the `rb-fsrs` gem (MIT) — a permissive, standalone
implementation of the Free Spaced Repetition Scheduler. None of Anki's AGPL
application code is used; only the independently-licensed FSRS algorithm.

## Stack

Rails 8 · SQLite · Hotwire (Turbo + Stimulus) · importmap · Tailwind v4 · RSpec.
Deployed with Kamal to mynewwords.org.

## Develop

- `bin/dev` — Rails + Tailwind watcher
- `bundle exec rspec` — tests
- `bin/kamal deploy` — ship to prod
