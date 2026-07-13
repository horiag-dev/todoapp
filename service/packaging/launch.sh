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

# Subscription OAuth should win over stray API credentials inherited from a shell.
# Set BIGROCKS_USE_ENV_AUTH=1 only if your company intentionally uses API/Bedrock/etc.
if [ "${BIGROCKS_USE_ENV_AUTH:-0}" != "1" ]; then
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN
  unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
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
