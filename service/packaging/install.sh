#!/bin/sh
set -eu

APP_NAME="Big Rocks First"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR="$SCRIPT_DIR/app"
INSTALL_DIR=${BIGROCKS_INSTALL_DIR:-"$HOME/.local/share/big-rocks-first"}
BIN_DIR=${BIGROCKS_BIN_DIR:-"$HOME/.local/bin"}
APPLICATIONS_DIR=${BIGROCKS_APPLICATIONS_DIR:-"$HOME/Applications"}
STATE_DIR=${BIGROCKS_STATE_DIR:-"$HOME/Library/Application Support/Big Rocks First"}
LAUNCHER="$BIN_DIR/big-rocks-first"
APP_BUNDLE="$APPLICATIONS_DIR/Big Rocks First.app"

say() { printf '%s\n' "$*"; }
fail() { say "Error: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this package is for macOS"
[ -f "$SOURCE_DIR/package.json" ] || fail "the app payload is missing; run this installer from the extracted package"
command -v node >/dev/null 2>&1 || fail "Node.js 18 or newer is required. Install Node.js, then run ./install.sh again."
command -v npm >/dev/null 2>&1 || fail "npm is required. Install a current Node.js distribution, then run ./install.sh again."

NODE_MAJOR=$(node -p 'Number(process.versions.node.split(".")[0])')
[ "$NODE_MAJOR" -ge 18 ] || fail "Node.js 18 or newer is required; found $(node --version)"

say "Installing ${APP_NAME}…"
PARENT_DIR=$(dirname "$INSTALL_DIR")
STAGE="$INSTALL_DIR.install.$$"
BACKUP="$INSTALL_DIR.previous.$$"
mkdir -p "$PARENT_DIR" "$BIN_DIR" "$APPLICATIONS_DIR" "$STATE_DIR"
rm -rf "$STAGE" "$BACKUP"
mkdir -p "$STAGE"
cp -R "$SOURCE_DIR/." "$STAGE/"

say "Installing locked application dependencies for $(uname -m)…"
(cd "$STAGE" && npm ci --omit=dev)

if [ -d "$INSTALL_DIR" ]; then mv "$INSTALL_DIR" "$BACKUP"; fi
mv "$STAGE" "$INSTALL_DIR"
rm -rf "$BACKUP"

cp "$SCRIPT_DIR/launch.sh" "$LAUNCHER"
chmod 755 "$LAUNCHER"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cat > "$APP_BUNDLE/Contents/MacOS/Big Rocks First" <<'APP_LAUNCHER'
#!/bin/sh
exec "${BIGROCKS_BIN_DIR:-$HOME/.local/bin}/big-rocks-first" "$@"
APP_LAUNCHER
chmod 755 "$APP_BUNDLE/Contents/MacOS/Big Rocks First"

if [ "${BIGROCKS_SKIP_CLAUDE_CHECK:-0}" != "1" ]; then
  if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || \
     [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ] || \
     [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ] || [ "${CLAUDE_CODE_USE_FOUNDRY:-}" = "1" ]; then
    # A sanctioned API/environment credential is present — the agent will use it.
    # This is the right path on a managed/work Mac (a personal subscription login
    # is often blocked and would get the agent killed), so we skip the login step.
    say ""
    say "Detected Anthropic API/environment credentials — the agent will use those."
    say "No personal Claude login needed. The launcher keeps this key on every start."
  else
    # No env credentials found — fall back to a personal Claude subscription login.
    if ! command -v claude >/dev/null 2>&1; then
      say "No API key found. Installing the Claude Code CLI for subscription login…"
      npm install -g @anthropic-ai/claude-code || fail "Claude Code installation failed. Install it using Anthropic's official instructions, then rerun this installer."
    fi

    if ! claude auth status >/dev/null 2>&1; then
      say ""
      say "Sign in with your Claude subscription (or set a work ANTHROPIC_API_KEY and rerun):"
      claude auth login || true
    fi

    say ""
    say "Claude authentication:"
    claude auth status --text 2>/dev/null || true
  fi
fi

say ""
say "$APP_NAME installed successfully."
say "App:     $APP_BUNDLE"
say "Command: $LAUNCHER"
say "Data:    Choose your Markdown file on first launch; it is never copied into the app."

if [ "${BIGROCKS_SKIP_LAUNCH:-0}" != "1" ]; then
  "$LAUNCHER" --restart
fi
