#!/usr/bin/env bash
# session-boot.sh (polyglot) — Runs at SessionStart via the hook in
# .claude/settings.json.
#
# This repo is a STANDALONE sibling of the OCL repos (git remote: polyglot),
# not part of the OCL monorepo family. It reuses ocl's session-tooling scripts
# via up-symlinks in .claude/scripts/ (the real files live in ocl/.claude/scripts/),
# but keeps its OWN siloed session list in this repo's .claude/sessions-active/.
#
# Derived from the web-repo boot, with the OCL-only bits stripped:
#   - no statusline self-heal (OCL footer renderer)
#   - no Kanban WIP block (OCL project board)
#   - no GitHub issue-title fetch (OCL issue tracker / localhost endpoint)
#
# What it does:
#   1. Registers a manifest with a unique animal name in .claude/sessions-active/
#   2. Applies the iTerm tab color + title from the animal name
#   3. Sweeps local-dead manifests left by crashes / force-closes
#   4. Lists other live sessions (siloed to THIS repo)
#   5. Emits the SESSION_BOOT_REPORT the assistant presents as a greeting

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
MANIFEST_DIR="$REPO_ROOT/.claude/sessions-active"

# Stable claude process PID (not the transient $PPID).
source "$REPO_ROOT/.claude/scripts/claude-pid.sh"
MY_PID="$CLAUDE_PID"

# 1. Register this session's manifest with a cool name.
#    Idempotent: reuse existing manifest/name if this claude_pid already has one.
mkdir -p "$MANIFEST_DIR"
TTY=$(ps -o tty= -p "$MY_PID" 2>/dev/null | tr -d ' ' || echo "unknown")
MANIFEST_FILE="$MANIFEST_DIR/ocl_session_$MY_PID.json"

EXISTING_NAME=$(python3 -c "import json,sys; print((json.load(open(sys.argv[1])).get('session_name') or '').strip())" "$MANIFEST_FILE" 2>/dev/null || echo "")

if [ -n "$EXISTING_NAME" ]; then
  SESSION_NAME="$EXISTING_NAME"
else
  SESSION_NAME=$(bash "$REPO_ROOT/.claude/scripts/session-name.sh" "$MANIFEST_DIR")

  # started_at from the Claude process's actual start time (ps lstart), not
  # write-time `date -u` — the liveness check compares (now - started_at) against
  # the process etime, and a write-time stamp that lags the true start reads as
  # PID-reuse and gets the live session swept. Defensive fallback to `date -u`.
  LSTART=$(ps -p "$MY_PID" -o lstart= 2>/dev/null | xargs)
  STARTED_AT=""
  if [ -n "$LSTART" ]; then
    LSTART_EPOCH=$(date -j -f "%a %b %d %H:%M:%S %Y" "$LSTART" +%s 2>/dev/null || echo "")
    if [ -n "$LSTART_EPOCH" ]; then
      STARTED_AT=$(date -u -r "$LSTART_EPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
                || date -u -d "@$LSTART_EPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
                || echo "")
    fi
  fi
  [ -z "$STARTED_AT" ] && STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  HEARTBEAT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cat > "$MANIFEST_FILE" <<MANIFEST
{"claude_pid":$MY_PID,"bash_pid":$$,"tty":"$TTY","session_name":"$SESSION_NAME","started_at":"$STARTED_AT","last_heartbeat_at":"$HEARTBEAT_AT","work_type":null,"issue":null,"description":null,"topic":null,"files_touched":[]}
MANIFEST
fi

# 2. Re-apply tab color + title on every boot (not just first) so /compact or a
#    resume doesn't lose the animal emoji.
ISSUE_TEXT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('issue') or '')" "$MANIFEST_FILE" 2>/dev/null || echo "")
TITLE_TEXT="${ISSUE_TEXT:-$SESSION_NAME}"
OCL_TAB_TTY="$TTY" bash "$REPO_ROOT/.claude/scripts/tab-color.sh" "${SESSION_NAME%%-*}" 2>/dev/null || true
bash "$REPO_ROOT/.claude/scripts/work-title.sh" "$TITLE_TEXT" 2>/dev/null || true

# 3. Sweep local-dead manifests from prior crashes / force-closes. Safe by
#    design — only archives manifests where kill -0 fails AND host=current.
#    Honors OCL_DISABLE_AUTO_ARCHIVE=1 (handled inside the script).
SWEPT_OUTPUT=$(CLAUDE_REPO_ROOT="$REPO_ROOT" bash "$REPO_ROOT/.claude/scripts/archive-stale-sessions.sh" --local-dead-only 2>/dev/null || echo "")
# Per-archived lines look like "archived: <name>  (pid ...) — ...". The trailing
# summary line "archived: 0   alive: 0   own (skipped): 1" also starts with
# "archived:" — exclude it by requiring a non-numeric second field (the name).
SWEPT_NAMELINES=$(echo "$SWEPT_OUTPUT" | awk '/^archived:/ && $2 !~ /^[0-9]+$/ { print $2 }')
SWEPT_NAMES=$(echo "$SWEPT_NAMELINES" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
SWEPT_COUNT=$(echo "$SWEPT_NAMELINES" | grep -c . || echo 0)

# 4. Git info.
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
GIT_STATUS=$(git status --short 2>/dev/null || echo "")
AHEAD=$(git log --oneline origin/main..HEAD 2>/dev/null | wc -l | tr -d ' ')
BEHIND=$(git log --oneline HEAD..origin/main 2>/dev/null | wc -l | tr -d ' ')

# 5. Other sessions — per-manifest liveness (DEAD skip, STALE suffix, ALIVE show).
LIVENESS_SCRIPT="$REPO_ROOT/.claude/scripts/check-session-liveness.sh"
OTHER_SESSIONS=""
for manifest in "$MANIFEST_DIR"/ocl_session_*.json; do
  [ -f "$manifest" ] || continue
  pid=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('claude_pid',''))" "$manifest" 2>/dev/null || continue)
  [ "$pid" = "$MY_PID" ] && continue

  liveness=$(bash "$LIVENESS_SCRIPT" "$manifest" 2>/dev/null || echo "alive")
  case "$liveness" in dead*) continue ;; esac

  name_for_emoji=$(jq -r '.session_name // ""' "$manifest" 2>/dev/null)
  emoji=$(bash "$REPO_ROOT/.claude/scripts/animal-emoji.sh" "${name_for_emoji##*-}" 2>/dev/null || echo "")

  info=$(LIVENESS="$liveness" EMOJI="$emoji" python3 -c "
import json, datetime, sys, os
d = json.load(open(sys.argv[1]))
name = d.get('session_name') or 'unnamed'
issue = d.get('issue')
desc = d.get('description')
wtype = d.get('work_type')
tty = d.get('tty') or '?'
started = d.get('started_at', '')
liveness = os.environ.get('LIVENESS', 'alive')
emoji = os.environ.get('EMOJI', '')
prefix = (emoji + ' ') if emoji else ''
suffix = ' (may be stale)' if liveness == 'stale' else ''
age = ''
if started:
    try:
        st = datetime.datetime.fromisoformat(started.replace('Z', '+00:00'))
        delta = datetime.datetime.now(datetime.timezone.utc) - st
        mins = int(delta.total_seconds() / 60)
        age = (str(mins) + 'm ago') if mins < 60 else (str(mins // 60) + 'h ' + str(mins % 60) + 'm ago')
    except: pass
if wtype and issue and desc:
    print(prefix + name + ' (tty ' + tty + '): ' + wtype + ' — ' + issue + ' — ' + desc + suffix)
elif wtype and desc:
    print(prefix + name + ' (tty ' + tty + '): ' + wtype + ' — ' + desc + suffix)
elif issue:
    print(prefix + name + ' (tty ' + tty + '): ' + issue + suffix)
else:
    print(prefix + name + ' (tty ' + tty + '): idle (booted ' + (age or started) + ')' + suffix)
" "$manifest" 2>/dev/null || echo "PID $pid: unknown")
  if [ -n "$OTHER_SESSIONS" ]; then
    OTHER_SESSIONS="$OTHER_SESSIONS\n$info"
  else
    OTHER_SESSIONS="$info"
  fi
done

# 6. Build report.
REPORT="SESSION_BOOT_REPORT\n"
REPORT+="session_name: $SESSION_NAME\n"
REPORT+="my_pid: $MY_PID\n"
REPORT+="my_tty: $TTY\n"
REPORT+="branch: $BRANCH\n"
REPORT+="ahead: $AHEAD\n"
REPORT+="behind: $BEHIND\n"
REPORT+="---git_status---\n"
REPORT+="$GIT_STATUS\n"
REPORT+="---other_sessions---\n"
REPORT+="$(echo -e "$OTHER_SESSIONS")\n"

if [ "${SWEPT_COUNT:-0}" -gt 0 ] 2>/dev/null; then
  REPORT+="---boot_sweep---\n"
  REPORT+="swept $SWEPT_COUNT dead local manifest(s): $SWEPT_NAMES\n"
fi

REPORT+="---end---"

echo -e "$REPORT"

# Bump OWN heartbeat at end of boot so a freshly-booted session is never seen as
# stale by another session's sweep before its first tool call fires.
bash "$REPO_ROOT/.claude/scripts/bump-heartbeat.sh" 2>/dev/null || true
