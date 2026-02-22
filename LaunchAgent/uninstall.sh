#!/usr/bin/env bash

set -euo pipefail

LABEL="dev.pruiz.LoginShot"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/LoginShot"
PURGE_LOGS="false"

usage() {
    cat <<EOF
Uninstall LoginShot LaunchAgent for current user.

Usage:
  $(basename "$0") [--purge-logs] [--help]

Options:
  --purge-logs   Remove ~/Library/Logs/LoginShot
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --purge-logs)
        PURGE_LOGS="true"
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Error: Unknown argument: %s\n' "$1" >&2
        exit 1
        ;;
    esac
done

UID_VALUE="$(id -u)"
launchctl bootout "gui/$UID_VALUE" "$PLIST_PATH" >/dev/null 2>&1 || true

if [[ -f "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
    printf 'Removed LaunchAgent plist: %s\n' "$PLIST_PATH"
else
    printf 'LaunchAgent plist not present: %s\n' "$PLIST_PATH"
fi

if [[ "$PURGE_LOGS" == "true" ]]; then
    if [[ -d "$LOG_DIR" ]]; then
        rm -rf "$LOG_DIR"
        printf 'Removed logs: %s\n' "$LOG_DIR"
    else
        printf 'Log directory not present: %s\n' "$LOG_DIR"
    fi
fi

printf 'LaunchAgent uninstall complete for label: %s\n' "$LABEL"
