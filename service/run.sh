#!/bin/sh
# Big Rocks First — run as a plain local service (no app bundle, no installer).
#
#   tar xzf big-rocks-first-service-*.tar.gz
#   cd big-rocks-first-service-*
#   sh run.sh                       # then open http://127.0.0.1:5178
#
# Start it from a Terminal so it inherits your environment — including a
# work-sanctioned ANTHROPIC_API_KEY, exactly like Sparkline. Nothing here is an
# "app", so Gatekeeper has no bundle to flag. Ctrl-C stops it.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"
PORT=${PORT:-5178}
URL="http://127.0.0.1:$PORT"

command -v node >/dev/null 2>&1 || {
  echo "Node.js 18+ is required — install from https://nodejs.org or 'brew install node', then rerun." >&2
  exit 1
}

# Install locked dependencies on first run (and after an update, when the
# lockfile is newer than node_modules). Built for THIS machine's architecture.
if [ ! -d node_modules ] || [ package-lock.json -nt node_modules ]; then
  command -v npm >/dev/null 2>&1 || {
    echo "npm is missing and dependencies aren't installed. Install Node.js (it includes npm) and rerun." >&2
    exit 1
  }
  echo "Installing dependencies (first run)…"
  npm ci --omit=dev || npm install --omit=dev
fi

# Open the browser once the server answers (backgrounded; harmless if it never does).
if [ "${BIGROCKS_SKIP_OPEN:-0}" != "1" ]; then
  ( i=0; while [ "$i" -lt 100 ]; do
      curl -fsS "$URL/api/model" >/dev/null 2>&1 && { open "$URL" 2>/dev/null || true; break; }
      i=$((i + 1)); sleep 0.1
    done ) &
fi

echo "Big Rocks First → $URL   (Ctrl-C to stop)"
exec node src/server.mjs
