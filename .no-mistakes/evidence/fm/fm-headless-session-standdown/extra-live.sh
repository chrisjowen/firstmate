#!/usr/bin/env bash
set -u
ROOT=$1; LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-extra.XXXXXX"); trap 'rm -rf "$LAB"' EXIT
unset NO_MISTAKES_GATE FM_SESSIONSTART_ALLOW_UNATTENDED FM_NO_LOCK FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS CLAUDECODE CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_SESSION_ID CLAUDE_CODE_ENTRYPOINT
mk() { local l="$LAB/$1"; git clone -q "$ROOT" "$l" 2>/dev/null; cp -R "$ROOT/bin/." "$l/bin/"; mkdir -p "$l/state" "$l/data" "$l/config"
  jq '{hooks:{SessionStart:.hooks.SessionStart}}' "$ROOT/.claude/settings.json" > "$l/.claude/settings.json"
  cat > "$l/.claude/settings.local.json" <<'J'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"printf 'ATTENDED=%s FM_NO_LOCK=%s\\n' \"${CLAUDE_CODE_SESSION_ATTENDED-unset}\" \"${FM_NO_LOCK-unset}\" > \"$CLAUDE_PROJECT_DIR/probe\""}]}]}}
J
  echo "$l"; }
report() { echo "  probe: $(cat "$1/probe" 2>/dev/null || echo MISSING)"; if [ -e "$1/state/.lock" ]; then echo "  state/.lock: PRESENT (pid $(cat "$1/state/.lock"))"; else echo "  state/.lock: absent"; fi; }
if [ -z "${SKIPAB:-}" ]; then
echo "== Case A: exact docket reviewer command, launched bare (claude -p ... --model haiku --no-session-persistence --permission-mode dontAsk), cwd=home"
l=$(mk docket); (cd "$l" && FM_HOME="$l" claude -p 'Reply with exactly: ok' --model haiku --no-session-persistence --permission-mode dontAsk) </dev/null >"$l/out" 2>&1; echo "  claude exit=$? out=$(head -c 80 "$l/out")"; report "$l"
echo "== Case B: FM_NO_LOCK=1 + FM_SESSIONSTART_ALLOW_UNATTENDED=1 claude -p (override must NOT beat FM_NO_LOCK)"
l=$(mk nolock); (cd "$l" && FM_HOME="$l" FM_NO_LOCK=1 FM_SESSIONSTART_ALLOW_UNATTENDED=1 claude -p 'Reply with exactly: ok' --model haiku --no-session-persistence --permission-mode dontAsk) </dev/null >"$l/out" 2>&1; echo "  claude exit=$? out=$(head -c 80 "$l/out")"; report "$l"
fi
echo "== Case C: interactive (attended) claude in a private tmux socket, cwd=home"
l=$(mk interactive); mkdir -p "$LAB/tmux"
TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab new-session -d -x 200 -y 50 -s primary -c "$l" -e FM_HOME="$l" "claude --model haiku"
for i in $(seq 1 30); do TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab capture-pane -p -t primary | grep -q "trust this folder" && { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab send-keys -t primary Down; sleep 0.5; TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab send-keys -t primary Enter; break; }; sleep 1; done
for i in $(seq 1 60); do [ -e "$l/state/.lock" ] && [ -e "$l/probe" ] && break; sleep 1; done
sleep 3; report "$l"
echo "  pane tail:"; TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab capture-pane -p -t primary | grep -v '^\s*$' | tail -8 | sed 's/^/    /'
echo "== Case D: FM_NO_LOCK=1 interactive (attended) claude"
l=$(mk interactive-nolock)
TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab new-session -d -x 200 -y 50 -s nolock -c "$l" -e FM_HOME="$l" -e FM_NO_LOCK=1 "claude --model haiku"
for i in $(seq 1 30); do TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab capture-pane -p -t nolock | grep -q "trust this folder" && { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab send-keys -t nolock Down; sleep 0.5; TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab send-keys -t nolock Enter; break; }; sleep 1; done
for i in $(seq 1 60); do [ -e "$l/probe" ] && break; sleep 1; done
sleep 8; report "$l"
TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server
