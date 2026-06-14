#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"
cd "$REPO_DIR"

scripts/package_app.sh

APP_NAME="DontSwitchMics.app"
SOURCE_APP="dist/$APP_NAME"
INSTALLED_APP="/Applications/$APP_NAME"

if rm -rf "$INSTALLED_APP" && cp -R "$SOURCE_APP" "$INSTALLED_APP"; then
    :
else
    HOME_APPS="$HOME/Applications"
    mkdir -p "$HOME_APPS"
    INSTALLED_APP="$HOME_APPS/$APP_NAME"
    rm -rf "$INSTALLED_APP"
    cp -R "$SOURCE_APP" "$INSTALLED_APP"
fi

open "$INSTALLED_APP"
echo "Installed and opened $INSTALLED_APP"
