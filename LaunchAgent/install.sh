#!/usr/bin/env bash

set -euo pipefail

LABEL="dev.pruiz.LoginShot"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/dev.pruiz.LoginShot.plist.template"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/LoginShot"
STDOUT_LOG="$LOG_DIR/agent.out.log"
STDERR_LOG="$LOG_DIR/agent.err.log"
DEFAULT_APP_SYSTEM="/Applications/LoginShot.app"
DEFAULT_APP_USER="$HOME/Applications/LoginShot.app"

usage() {
    cat <<EOF
Install LoginShot LaunchAgent for current user.

Usage:
  $(basename "$0") [--app /path/to/LoginShot.app] [--help]

Defaults (strict):
  1) /Applications/LoginShot.app
  2) ~/Applications/LoginShot.app

Use --app when LoginShot.app is installed elsewhere.
EOF
}

error() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

APP_BUNDLE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --app)
        [[ $# -ge 2 ]] || error "Missing value for --app"
        APP_BUNDLE="$2"
        shift 2
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        error "Unknown argument: $1"
        ;;
    esac
done

if [[ -z "$APP_BUNDLE" ]]; then
    if [[ -d "$DEFAULT_APP_SYSTEM" ]]; then
        APP_BUNDLE="$DEFAULT_APP_SYSTEM"
    elif [[ -d "$DEFAULT_APP_USER" ]]; then
        APP_BUNDLE="$DEFAULT_APP_USER"
    else
        error "LoginShot.app not found in /Applications or ~/Applications. Use --app /path/to/LoginShot.app"
    fi
fi

APP_BUNDLE="$(cd "$APP_BUNDLE" && pwd)"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/LoginShot"

[[ -f "$TEMPLATE_PATH" ]] || error "Missing template: $TEMPLATE_PATH"
[[ -d "$APP_BUNDLE" ]] || error "App bundle not found: $APP_BUNDLE"
[[ -x "$APP_EXECUTABLE" ]] || error "App executable not found or not executable: $APP_EXECUTABLE"

mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$LOG_DIR"

python3 - "$TEMPLATE_PATH" "$PLIST_PATH" "$APP_EXECUTABLE" "$STDOUT_LOG" "$STDERR_LOG" <<'PY'
import html
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
plist_path = pathlib.Path(sys.argv[2])
app_executable = html.escape(sys.argv[3])
stdout_log = html.escape(sys.argv[4])
stderr_log = html.escape(sys.argv[5])

template = template_path.read_text(encoding="utf-8")
rendered = (
    template
    .replace("__APP_EXECUTABLE_PATH__", app_executable)
    .replace("__STDOUT_PATH__", stdout_log)
    .replace("__STDERR_PATH__", stderr_log)
)
plist_path.write_text(rendered, encoding="utf-8")
PY

UID_VALUE="$(id -u)"
launchctl bootout "gui/$UID_VALUE" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID_VALUE/$LABEL"

cat <<EOF
Installed LaunchAgent: $PLIST_PATH
App executable: $APP_EXECUTABLE

Verification:
  launchctl print gui/$UID_VALUE/$LABEL

Logs:
  $STDOUT_LOG
  $STDERR_LOG
EOF
