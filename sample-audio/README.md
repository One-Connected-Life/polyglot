# sample-audio/ — local test recordings (NEVER committed)

Drop real audio here to test the audio→vocab pipeline (issue #3): voicemails,
overheard conversations, movie clips.

**Everything in this folder except this README is gitignored and must stay that way.**
The motivating use case is official/medical Dutch voicemails — personal data. This
repo is **public on GitHub under AGPL**, so a single committed `.m4a` leaks real
personal data into permanent, forkable history.

- ✅ Drop your `.m4a` / `.mp3` / `.wav` files here for local dev + manual testing.
- ❌ Never `git add` an audio file here.
- ❌ Committed test fixtures (in `spec/fixtures/`) must be synthetic or public-domain,
  never your actual recordings.

See `docs/PRD-audio-to-vocab.md` for the feature spec and the privacy decision.
