#!/bin/sh
# Update Big Rocks First to the NEWEST downloaded service package, then run it.
#
#   sh update-big-rocks.sh                 # newest tarball in ~/Downloads -> ~/big-rocks-first
#   SEARCH_DIR="$HOME/Desktop" sh update-big-rocks.sh
#   DEST="$HOME/apps/bigrocks" PORT=5179 sh update-big-rocks.sh
#   sh update-big-rocks.sh --no-run        # refresh the install but don't start it
#
# Your data is never touched — todos live in your vault (.md) and chat/memory
# state lives in ~/.config/big-rocks-first, both outside the install dir.
set -eu

SEARCH_DIR=${SEARCH_DIR:-"$HOME/Downloads"}
DEST=${DEST:-"$HOME/big-rocks-first"}
PORT=${PORT:-5178}
RUN=1
[ "${1:-}" = "--no-run" ] && RUN=0

# 1) Newest downloaded package (by modification time).
TARBALL=$(ls -t "$SEARCH_DIR"/big-rocks-first-service-*.tar.gz 2>/dev/null | head -1 || true)
[ -n "${TARBALL:-}" ] || { echo "No big-rocks-first-service-*.tar.gz in $SEARCH_DIR — set SEARCH_DIR to where you downloaded it." >&2; exit 1; }
echo "==> Newest package: $(basename "$TARBALL")"

# 2) Verify the checksum if the .sha256 is alongside it.
if [ -f "$TARBALL.sha256" ] && command -v shasum >/dev/null 2>&1; then
  if ( cd "$(dirname "$TARBALL")" && shasum -a 256 -c "$(basename "$TARBALL").sha256" ) >/dev/null 2>&1; then
    echo "==> Checksum OK"
  else
    echo "==> WARNING: checksum did not verify" >&2
  fi
fi

# 3) Stop a running Big Rocks server on the port (only if it is actually ours).
if command -v lsof >/dev/null 2>&1; then
  PID=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
  if [ -n "${PID:-}" ]; then
    if ps -p "$PID" -o command= 2>/dev/null | grep -q "server.mjs"; then
      echo "==> Stopping running server (pid $PID) on port $PORT"
      kill "$PID" 2>/dev/null || true
      sleep 1
    else
      echo "Port $PORT is in use by something that isn't Big Rocks (pid $PID). Aborting to be safe." >&2
      exit 1
    fi
  fi
fi

# 4) Extract fresh into $DEST.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
tar xzf "$TARBALL" -C "$TMP"
EXTRACTED=$(ls -d "$TMP"/big-rocks-first-service-*/ 2>/dev/null | head -1 || true)
[ -n "${EXTRACTED:-}" ] || { echo "Unexpected package layout." >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
mv "$EXTRACTED" "$DEST"
rm -rf "$TMP"; trap - EXIT INT TERM
echo "==> Installed to $DEST"

# 5) Run it (installs locked deps on first launch; Ctrl-C to stop).
if [ "$RUN" = "1" ]; then
  echo "==> Starting… open http://127.0.0.1:$PORT (Ctrl-C to stop)"
  cd "$DEST"
  PORT="$PORT" exec sh run.sh
else
  echo "==> Done. Start it with:  cd \"$DEST\" && sh run.sh"
fi
