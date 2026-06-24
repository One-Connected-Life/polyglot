---
name: handoff
description: Write a resume snapshot before ending a Polyglot session so the next session picks up cleanly. Lightweight, memory-based — no session-manifest infra (unlike OCL's /handoff-restart). Use when context is getting long, switching machines, or deliberately parking work.
argument-hint: (none — captures current state)
user-invocable: true
---

# /handoff — Polyglot resume snapshot

Polyglot has **no session-manifest infra** (no `.claude/sessions-active/`, heartbeats,
or archive scripts — those are OCL-only). Resume here works purely through **memory
files**, which auto-load via `MEMORY.md` into the next session. This skill writes that
snapshot. It does NOT archive a manifest or restart anything.

## Steps

1. **Sweep uncommitted state.** Run `git status --short` and `git log origin/<branch>..<branch> --oneline`.
   Report any uncommitted or unpushed work to the user — Polyglot is solo and ships fast,
   so usually the right move is commit + push (and deploy if a feature is green) BEFORE
   handing off. Don't hand off broken or unpushed work silently.

2. **Write ONE resume memory** in this project's memory dir (the same dir `MEMORY.md`
   lives in), following the project memory convention:
   - `name`: `polyglot_session_handoff_<YYYY_MM_DD>` (reuse/overwrite same-day).
   - `metadata.type: project`.
   - `description`: lead with `RESUME SNAPSHOT (<date>, prune when <condition>)`.
   - Body: **The ONE thing left** (the single most important next action) · **Live/shipped**
     (what's deployed) · **Open / awaiting Mihai** (decisions parked on him) · **Branches**
     (which branch holds what, deployed or not). Convert relative dates to absolute.
     Link related memories with `[[name]]`. Keep it tight — it's a snapshot, not a log.

3. **Add/refresh the `MEMORY.md` pointer** — one line under `## Project`, top of section,
   with the ⏯ RESUME prefix and a prune hint. Replace any prior same-purpose pointer.

4. **Mark it TRANSIENT.** The body's first line says `**TRANSIENT handoff — prune when stale.**`
   so a future session knows to delete it once consumed.

5. **Tell the user** in one line: where the snapshot is (fenced absolute path) and the ONE
   next action it captured. Then stop — don't restart or clear.

## Not this skill's job
- No manifest archive, no `/clear`, no tab reset, no heartbeat — Polyglot has none of that.
- If you need OCL's full session lifecycle, that's `/handoff-restart` in the OCL repo (it
  won't run here — it depends on `.claude/sessions-active/`).
