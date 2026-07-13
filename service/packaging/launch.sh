#!/bin/sh
set -eu

APP_DIR=${BIGROCKS_INSTALL_DIR:-"$HOME/.local/share/big-rocks-first"}
STATE_DIR=${BIGROCKS_STATE_DIR:-"$HOME/Library/Application Support/Big Rocks First"}
LOG_DIR=${BIGROCKS_LOG_DIR:-"$HOME/Library/Logs/Big Rocks First"}
PORT=${PORT:-5178}
URL="http://127.0.0.1:$PORT"
PID_FILE="$STATE_DIR/service.pid"
LOG_FILE="$LOG_DIR/service.log"

mkdir -p "$STATE_DIR" "$LOG_DIR"
# GUI/launchd launches inherit a minimal PATH; make sure Homebrew node and the
# Claude CLI (~/.local/bin) are discoverable regardless of how we were started.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
[ -f "$APP_DIR/src/server.mjs" ] || { echo "Big Rocks First is not installed at $APP_DIR" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Node.js is required." >&2; exit 1; }

stop_service() {
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null || true
      COUNT=0
      while kill -0 "$PID" 2>/dev/null && [ "$COUNT" -lt 30 ]; do
        sleep 0.1
        COUNT=$((COUNT + 1))
      done
    fi
    rm -f "$PID_FILE"
  fi
}

if [ "${1:-}" = "--stop" ]; then stop_service; exit 0; fi
if [ "${1:-}" = "--restart" ]; then stop_service; fi

if curl -fsS "$URL/api/model" >/dev/null 2>&1; then
  if [ "${BIGROCKS_SKIP_OPEN:-0}" != "1" ]; then open "$URL"; fi
  exit 0
fi

# --- Agent authentication ---------------------------------------------------
# Managed/work Macs usually allow api.anthropic.com with a sanctioned
# ANTHROPIC_API_KEY but BLOCK a personal Claude subscription login — the agent's
# Claude Code child then gets killed (SIGKILL). So by DEFAULT we use whatever
# credentials the environment provides. Finder/Dock launches don't inherit your
# shell's exported vars, so when none are present we recover them from
# `launchctl` and from your login shell (~/.zprofile / ~/.zshrc, where a work key
# usually lives). Set BIGROCKS_FORCE_SUBSCRIPTION=1 to ignore all of this and
# force a personal Claude subscription (OAuth) login instead.
AUTH_VARS="ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY"
have_env_auth() {
  [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] ||
    [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ] ||
    [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ] || [ "${CLAUDE_CODE_USE_FOUNDRY:-}" = "1" ]
}
if [ "${BIGROCKS_FORCE_SUBSCRIPTION:-0}" = "1" ]; then
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN || true
  unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY || true
elif ! have_env_auth; then
  # (a) values published to the GUI session via `launchctl setenv`
  for v in $AUTH_VARS; do
    eval "cur=\${$v:-}"
    if [ -z "$cur" ]; then
      val=$(launchctl getenv "$v" 2>/dev/null || true)
      [ -n "$val" ] && export "$v=$val"
    fi
  done
  # (b) values exported in your login shell profile (covers Dock/Finder launches)
  if ! have_env_auth; then
    HARVEST=$("${SHELL:-/bin/zsh}" -lic '
      for v in '"$AUTH_VARS"'; do
        eval "vv=\"\${$v-}\""
        [ -n "$vv" ] && printf "BRAUTH:%s=%s\n" "$v" "$vv"
      done' 2>/dev/null || true)
    while IFS= read -r line; do
      case "$line" in BRAUTH:*) export "${line#BRAUTH:}" || true ;; esac
    done <<EOF
$HARVEST
EOF
  fi
fi
if have_env_auth; then
  echo "[big-rocks-first] agent auth: using API/environment credentials" >> "$LOG_FILE" 2>/dev/null || true
else
  echo "[big-rocks-first] agent auth: no env key found; will use a Claude subscription login if present. If chat is killed, export a work ANTHROPIC_API_KEY." >> "$LOG_FILE" 2>/dev/null || true
fi

(
  cd "$APP_DIR"
  nohup node src/server.mjs </dev/null >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
)

COUNT=0
while ! curl -fsS "$URL/api/model" >/dev/null 2>&1; do
  COUNT=$((COUNT + 1))
  if [ "$COUNT" -ge 80 ]; then
    echo "Big Rocks First did not start. See $LOG_FILE" >&2
    exit 1
  fi
  sleep 0.1
done

if [ "${BIGROCKS_SKIP_OPEN:-0}" != "1" ]; then open "$URL"; fi
