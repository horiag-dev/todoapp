#!/bin/sh
set -eu

SERVICE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO_DIR=$(CDPATH= cd -- "$SERVICE_DIR/.." && pwd)
VERSION=${1:-$(node -p "require('$SERVICE_DIR/package.json').version" 2>/dev/null || echo 0.0.0)}
NAME="big-rocks-first-macos-$VERSION"
OUT_DIR=${BIGROCKS_PACKAGE_OUT:-"$REPO_DIR/dist"}
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/big-rocks-package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM

ROOT="$STAGE/$NAME"
mkdir -p "$ROOT/app" "$OUT_DIR"
cp "$SERVICE_DIR/packaging/install.sh" "$ROOT/install.sh"
cp "$SERVICE_DIR/packaging/launch.sh" "$ROOT/launch.sh"
cp "$SERVICE_DIR/packaging/Info.plist" "$ROOT/Info.plist"
cp "$SERVICE_DIR/packaging/README-INSTALL.md" "$ROOT/README-INSTALL.md"
cp "$SERVICE_DIR/package.json" "$ROOT/app/package.json"
cp "$SERVICE_DIR/package-lock.json" "$ROOT/app/package-lock.json"
cp "$SERVICE_DIR/README.md" "$ROOT/app/README.md"
cp -R "$SERVICE_DIR/src" "$ROOT/app/src"
cp -R "$SERVICE_DIR/public" "$ROOT/app/public"
cp -R "$SERVICE_DIR/test" "$ROOT/app/test"
cp -R "$SERVICE_DIR/fixtures" "$ROOT/app/fixtures"
chmod 755 "$ROOT/install.sh" "$ROOT/launch.sh"

tar -czf "$OUT_DIR/$NAME.tar.gz" -C "$STAGE" "$NAME"
(cd "$OUT_DIR" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
printf '%s\n' "$OUT_DIR/$NAME.tar.gz"
