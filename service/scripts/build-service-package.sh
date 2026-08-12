#!/bin/sh
# Build the PLAIN SERVICE package (Sparkline-style): a folder you extract and run
# with `sh run.sh`. No .app bundle, no installer, no ~/.local launcher — nothing
# for Gatekeeper/EDR to flag, and it inherits your Terminal's environment.
set -eu

SERVICE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO_DIR=$(CDPATH= cd -- "$SERVICE_DIR/.." && pwd)
VERSION=${1:-$(node -p "require('$SERVICE_DIR/package.json').version" 2>/dev/null || echo 0.0.0)}
NAME="big-rocks-first-service-$VERSION"
OUT_DIR=${BIGROCKS_PACKAGE_OUT:-"$REPO_DIR/dist"}
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/big-rocks-service.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM

ROOT="$STAGE/$NAME"
mkdir -p "$ROOT" "$OUT_DIR"

# Everything needed to run — and nothing else. No node_modules (run.sh installs
# them locally, matched to the target machine's architecture).
cp "$SERVICE_DIR/run.sh" "$ROOT/run.sh"
cp "$SERVICE_DIR/package.json" "$ROOT/package.json"
cp "$SERVICE_DIR/package-lock.json" "$ROOT/package-lock.json"
cp -R "$SERVICE_DIR/src" "$ROOT/src"
cp -R "$SERVICE_DIR/public" "$ROOT/public"
chmod 755 "$ROOT/run.sh"

cat > "$ROOT/README.md" <<'MD'
# Big Rocks First — service

A local Node service over your Markdown todo file. No app bundle, no installer.

## Run

```sh
sh run.sh
```

Then open http://127.0.0.1:5178 . Ctrl-C stops it.

Start it from a Terminal so it inherits your environment. On a work Mac, that
means it uses your sanctioned `ANTHROPIC_API_KEY` (the same way Sparkline does) —
the assistant/chat needs it. On a personal Mac with no key set, it falls back to
your Claude subscription login (`claude` CLI) automatically.

First run installs dependencies (needs Node.js 18+ and npm). Change the port
with `PORT=5179 sh run.sh`.
MD

tar -czf "$OUT_DIR/$NAME.tar.gz" -C "$STAGE" "$NAME"
( cd "$OUT_DIR" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )
echo "$OUT_DIR/$NAME.tar.gz"
