---
name: handoff-restart
description: Compact context in-place, write a resume-here doc, refresh the session in the same tab. Verbatim copy of OCL's proven /handoff-restart — adjust paths/infra for Polyglot as needed (see note).
argument-hint: (none — captures current state, then refreshes context)
user-invocable: true
---

> **⚠️ NOTE — this is a VERBATIM copy of OCL's `/handoff-restart` skill, dropped into Polyglot on 2026-06-25.**
> The mechanism below has worked in OCL for a month. It is reproduced AS-IS on purpose
> (the prior bespoke Polyglot `/handoff` reinvented a memory-write and was retired). **Make
> adjustments as needed when you actually run it here** — Polyglot differs from OCL in ways
> this text still assumes OCL:
> - **No session-manifest infra** in Polyglot (`.claude/sessions-active/`, heartbeats,
>   `archive-own-manifest.sh`, `claude-pid.sh`, the handoff sentinel, `handoff-clear-and-resume.sh`)
>   — Steps 1, 4, 5 and the manifest/SessionEnd machinery won't exist. Either skip them or
>   fall back to: write the doc, print the paste-this fallback, let Mihai paste `/clear` + resume.
> - **Handoff doc home:** OCL writes to `oneconnectedlife.org/docs/handoff/`. In Polyglot,
>   write to this repo (`docs/handoff/<slug>-resume-here.md`) OR — matching how Polyglot has
>   resumed for a month — to a **memory file** (`polyglot_session_handoff_<YYYY_MM_DD>` + a
>   `MEMORY.md` pointer), since `MEMORY.md` auto-loads into the next session.
> - Issue tracker is `One-Connected-Life/polyglot`, not the OCL Rails tracker.
> Trim/replace the OCL-specific bash as you go; don't run scripts that don't exist here.

# /handoff-restart — Compact context in-place, write a resume-here doc, fresh session

> Use when context is past ~250k tokens and the active work has natural pause points (or just settled decisions). Captures the minimum-viable handoff to disk, then refreshes context **in the SAME iTerm tab** via auto-dispatched `/clear` + resume command — no copy-paste required. Same animal name carries over via the existing sentinel mechanism.
>
> Aliased mentally as: `/restart-with-smaller-context-window`.
>
> **Heads-up — `/clear` triggers SessionEnd, which archives this session's manifest.** A fresh manifest is created by SessionStart on the new context. The animal name is preserved via the sentinel; `started_at` is not. If you need full state continuity, save what matters in the handoff doc — that IS the bridge.

## When to invoke

- Context window is large enough that prompt-cache misses are noticeably expensive
- Conversation has wandered through enough decisions that *you* are losing track of what you're asking
- The user says "let's restart" / "I'm losing the thread" / asks about token cost
- A natural pause point: just-settled decision set, plan posted, awaiting external input, finished a phase

## What to do

### Step 1: Identify the active work

Read the session manifest to find the active issue. Modern manifests are user-prefixed (`ocl_session_<user>_<pid>.json`); legacy ones aren't — try both, in that order:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
source "$REPO_ROOT/.claude/scripts/claude-pid.sh"
USER_SHORT=$(whoami 2>/dev/null || echo "unknown")
MANIFEST=""
for candidate in \
  "$REPO_ROOT/.claude/sessions-active/ocl_session_${USER_SHORT}_${CLAUDE_PID}.json" \
  "$REPO_ROOT/.claude/sessions-active/ocl_session_${CLAUDE_PID}.json"; do
  [ -f "$candidate" ] && MANIFEST="$candidate" && break
done
jq -r '"\(.issue // "no-issue") | \(.work_type // "—") | \(.description // "—")"' "$MANIFEST"
```

If no `issue`, ask the user what to title the handoff (they may be in a `task` cycle without one).

### Step 2: Write the handoff doc

> **Canonical handoff home is the web repo's `docs/handoff/` (#242, consolidated 2026-06-23).** Always write to `oneconnectedlife.org/docs/handoff/<slug>-resume-here.md` regardless of session CWD — never create a copy under the parent `/ocl` CWD.

Path: `oneconnectedlife.org/docs/handoff/<NNN>-resume-here.md` (or `oneconnectedlife.org/docs/handoff/<topic-slug>-resume-here.md` for non-issue work). When a session is booted from `/ocl` parent CWD, resolve the absolute path explicitly — do NOT use a bare relative `docs/handoff/` which would land in the parent. Capture the absolute path in `DOC_PATH` for Step 5 to dispatch.

```bash
# Always use the absolute path to the web repo's handoff dir — never a bare relative path
WEB_ROOT="/Users/mihai/coding/ocl/oneconnectedlife.org"   # or: git -C . rev-parse --show-toplevel if booted from web
DOC_PATH="${WEB_ROOT}/docs/handoff/<NNN>-resume-here.md"  # or <topic-slug>-resume-here.md
```

**Constraint:** the slug must match `[0-9a-zA-Z_/-]+` — letters, digits, hyphens, underscores, slashes only. The dispatcher script enforces this via regex (`^docs/handoff/[0-9a-zA-Z_/-]+-resume-here\.md$`) before keystroke-injecting it into iTerm — anything else is treated as a poisoned manifest and the auto-refresh aborts. (#884 security review Vuln 1+2.)

Include, concise (target ≤300 lines, ideally ≤150):

1. **One-line summary** of what the next session walks into
2. **State** — links to the canonical artifacts: GH issue, plan comment URL, spike docs, related backlog issues
3. **Decisions resolved this session** — table format, just the answers (the *reasoning* lives in GH issue comments / spike docs)
4. **Must-integrate gotchas** — bullet list of architect findings, race conditions, naming conventions, anything the next session would re-discover painfully
5. **Step 0 for next session** — concrete command-list to execute on resume (move to In Progress, set tab title, install gem, write first failing spec, etc.)
6. **What's open after this** — next-phase work, deferred decisions, related issues

### Step 3: Print the goodbye + paste-this fallback

Print exactly:

```
Handoff written: oneconnectedlife.org/docs/handoff/<NNN>-resume-here.md

Refreshing context in this tab in ~10s — don't type.

If the auto-refresh doesn't fire (e.g. iTerm permission prompt, off-screen
focus), paste manually:
  /clear
  Read oneconnectedlife.org/docs/handoff/<NNN>-resume-here.md and continue.

Cost saved: starts fresh at <50k context instead of <NNNk>.
```

The fallback paste-this lines are ALWAYS printed (not gated on a probe). If the dispatcher in Step 5 succeeds, the user ignores them. If it silently fails (TCC permission denial, focus race, iTerm not running), the user has a recovery path. See `#884` architect review C3.

### Step 4: Drop the handoff sentinel (#731)

Write a sentinel so the new session (post-`/clear`) inherits the animal name (different color = new context, same animal = continuity). Sentinel has a 10-min TTL and is consumed once by `session-name.sh`:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
# Walk up to /ocl if we're inside a child repo — sentinel lives at the parent
# so any new tab (parent CWD or web CWD) can find it.
PARENT_ROOT="$REPO_ROOT"
[ -d "$REPO_ROOT/../.claude/scripts" ] && PARENT_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
source "$REPO_ROOT/.claude/scripts/claude-pid.sh"
USER_SHORT=$(whoami 2>/dev/null || echo "unknown")
MANIFEST=""
for candidate in \
  "$REPO_ROOT/.claude/sessions-active/ocl_session_${USER_SHORT}_${CLAUDE_PID}.json" \
  "$REPO_ROOT/.claude/sessions-active/ocl_session_${CLAUDE_PID}.json"; do
  [ -f "$candidate" ] && MANIFEST="$candidate" && break
done
SESSION_NAME=$(jq -r '.session_name // ""' "$MANIFEST" 2>/dev/null)
ANIMAL="${SESSION_NAME##*-}"
COLOR="${SESSION_NAME%%-*}"
if [ -n "$ANIMAL" ] && [ -n "$COLOR" ]; then
  jq -n \
    --arg from_session "$SESSION_NAME" \
    --arg animal "$ANIMAL" \
    --arg exclude_color "$COLOR" \
    --arg written_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{from_session:$from_session, animal:$animal, exclude_color:$exclude_color, written_at:$written_at}' \
    > "$PARENT_ROOT/.claude/handoff-pending.json"
fi
```

### Step 5: Dispatch the in-place context refresh (#884)

Resolve the iTerm tty for THIS Claude process (NOT `$PPID` — Bash tool subshells have no tty), then background-dispatch `handoff-clear-and-resume.sh`. The script sleeps 3s, then sends `/clear` to the tty, polls iTerm session contents until the harness settles, then sends the resume command.

```bash
MY_TTY_NAME=$(ps -o tty= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ')
if [ -n "$MY_TTY_NAME" ] && [ "$MY_TTY_NAME" != "?" ]; then
  ( bash "$REPO_ROOT/.claude/scripts/handoff-clear-and-resume.sh" "$MY_TTY_NAME" "$DOC_PATH" ) &>/dev/null &
fi
```

**This must be the LAST foreground bash call in the skill.** Once it returns, Claude becomes idle, the goodbye text flushes, and ~3s later the dispatcher sends `/clear`. Any further tool calls would race with the incoming `/clear`.

**No manual archive call.** `/clear` triggers the `SessionEnd` hook (configured in `.claude/settings.json`), which runs `archive-own-manifest.sh` — the manifest is archived as a side-effect of the refresh. The sentinel dropped in Step 4 then carries the animal name into the new session.

**Ordering matters** — write the doc → print resume + fallback instructions → drop sentinel → dispatch refresh last. If the dispatcher fails silently, the user already has the printed paste-this fallback.

### Step 6: Surface anything that still needs answering

If there are unresolved questions (you were waiting on user input when this skill fired), make sure they're either:
- Resolved in the handoff (with your best-guess defaults, marked as such), OR
- Listed explicitly as open in the handoff

Don't lose decisions to a context reset.

## Rules

- **Do not invoke other skills inside this one** (no `/close-session`, no `/recap` — let the user chain).
- **Keep the handoff doc terse.** It's a bootstrap document, not a transcript. The next session can read GH comments and spike docs for full context.
- **Never close issues or revert code before handoff.** The user does that.
- **Manifest archiving happens via SessionEnd** (#884) — when `/clear` fires (either auto-dispatched in Step 5 or manually pasted via the fallback), the harness emits `SessionEnd`, which runs `archive-own-manifest.sh`. Do NOT call `archive-manifest.sh` directly from this skill — that would race with the SessionEnd hook and could double-archive. The new context's `SessionStart` consumes the sentinel from Step 4 and assigns the same animal name.
- If the active work has no GH issue and no clear topic, push back: "There's nothing to hand off — what would the next session even resume? Maybe just `/close-session`?"
