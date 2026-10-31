#!/usr/bin/env bash
# Live driver: real `claude -p` sessions in disposable Firstmate lab clones.
set -u
ROOT=$1 LAB=$2
mk() { local d="$LAB/$1"; git -c advice.detachedHead=false clone -q "$ROOT" "$d"; cp -R "$ROOT/bin/." "$d/bin/"; mkdir -p "$d/state" "$d/data" "$d/config" "$d/projects"; printf '%s\n' "$d"; }
clean() {
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u FM_NO_LOCK \
    -u FM_SESSIONSTART_ALLOW_UNATTENDED -u CLAUDE_JOB_DIR -u CLAUDE_CODE_SESSION_ID "$@"
}
lockstate() { if [ -e "$1/state/.lock" ]; then echo "YES (pid $(cat "$1/state/.lock"))"; else echo NO; fi; }

echo "### Scenario A: docket-shaped headless claude -p in the home, Bash allowed, told to run session start itself"
d=$(mk agentfallback)
(cd "$d" && clean CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=cli FM_HOME="$d" \
  claude -p 'Run exactly this shell command from the current directory and then reply with its full stdout and stderr verbatim, nothing else: bin/fm-session-start.sh; echo EXIT=$?' \
  --model haiku --no-session-persistence --dangerously-skip-permissions </dev/null 2>&1)
echo "--- fleet lock taken? $(lockstate "$d")"
echo "--- state dir: $(ls -A "$d/state" | tr '\n' ' ')"
echo

echo "### Scenario B: FM_NO_LOCK=1 + FM_SESSIONSTART_ALLOW_UNATTENDED=1 headless claude -p (override must not beat FM_NO_LOCK)"
d=$(mk nolock)
(cd "$d" && clean CLAUDE_CODE_SESSION_ATTENDED=1 FM_NO_LOCK=1 FM_SESSIONSTART_ALLOW_UNATTENDED=1 FM_HOME="$d" \
  claude -p 'Reply with exactly: ok' --model haiku --no-session-persistence --permission-mode dontAsk </dev/null 2>&1)
echo "--- fleet lock taken? $(lockstate "$d")"
echo "--- state dir: $(ls -A "$d/state" | tr '\n' ' ')"
