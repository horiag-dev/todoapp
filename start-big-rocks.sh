#!/bin/sh
# Start Big Rocks First — the everyday launcher for an ALREADY-INSTALLED copy.
#
#   sh start-big-rocks.sh              # start ~/big-rocks-first on port 5178
#   PORT=5179 sh start-big-rocks.sh    # a different port
#   DEST="$HOME/apps/bigrocks" sh start-big-rocks.sh
#   sh start-big-rocks.sh --restart    # stop a running copy first, then start
#   sh start-big-rocks.sh --stop       # just stop it
#
# This never touches the installed files. To install or upgrade to a newly
# downloaded package, use update-big-rocks.sh instead.
#
# Your data is never touched either — todos live in your vault (.md) and
# chat/memory state in ~/.config/big-rocks-first, both outside the install dir.
set -eu

DEST=${DEST:-"$HOME/big-rocks-first"}
PORT=${PORT:-5178}
URL="http://127.0.0.1:$PORT"
MODE=start
case "${1:-}" in
  --restart) MODE=restart ;;
  --stop) MODE=stop ;;
  --help|-h) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

# Is something already listening on the port, and is it ours? Never kill or
# report on a process that isn't Big Rocks — the port could be anything.
running_pid() {
  command -v lsof >/dev/null 2>&1 || return 0
  pid=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
  [ -n "${pid:-}" ] || return 0
  if ps -p "$pid" -o command= 2>/dev/null | grep -q "server.mjs"; then
    echo "$pid"
  else
    echo "Port $PORT is in use by something that isn't Big Rocks (pid $pid)." >&2
    echo "Use a different port:  PORT=5179 sh $(basename "$0")" >&2
    exit 1
  fi
}

stop_it() {
  pid=$(running_pid)
  [ -n "${pid:-}" ] || { [ "$MODE" = stop ] && echo "==> Not running on port $PORT."; return 0; }
  echo "==> Stopping Big Rocks (pid $pid) on port $PORT"
  kill "$pid" 2>/dev/null || true
  # Give it a moment to release the port, then insist.
  i=0
  while [ "$i" -lt 30 ] && kill -0 "$pid" 2>/dev/null; do i=$((i + 1)); sleep 0.1; done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
}

[ "$MODE" = stop ] && { stop_it; exit 0; }
[ "$MODE" = restart ] && stop_it

# Already up? Just bring the window forward rather than starting a second copy.
if [ -n "$(running_pid)" ]; then
  echo "==> Already running → $URL"
  [ "${BIGROCKS_SKIP_OPEN:-0}" = "1" ] || open "$URL" 2>/dev/null || true
  exit 0
fi

if [ ! -f "$DEST/run.sh" ]; then
  echo "No install found at $DEST." >&2
  echo "Install it first:  sh update-big-rocks.sh   (extracts the newest downloaded package)" >&2
  exit 1
fi

cd "$DEST"
exec env PORT="$PORT" sh run.sh
