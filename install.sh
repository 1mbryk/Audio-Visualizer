#!/bin/bash
#
# Installs Audio Visualizer from GitHub: downloads the source, builds it with Xcode
# and puts the app into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/1mbryk/Audio-Visualizer/main/install.sh | bash
#
# Settings (environment variables):
#   REF          branch, tag or commit to install (default: main)
#   INSTALL_DIR  where to put the app (default: /Applications)
#   REPO_URL     repository to clone (default: the GitHub one)
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/1mbryk/Audio-Visualizer.git}"
REF="${REF:-main}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_NAME="Audio Vusualizer"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "Audio Visualizer runs on macOS only."

macos="$(sw_vers -productVersion)"
if [[ "$(printf '%s\n' 27.2 "$macos" | sort -V | head -1)" != 27.2 ]]; then
    fail "macOS 27.2 or later is required (this Mac has $macos)."
fi

# The command line tools alone can't build an app: full Xcode is needed.
if ! xcodebuild -version >/dev/null 2>&1; then
    fail "Xcode is required to build the app. Install it from the App Store, open it once, then run:
       sudo xcode-select -s /Applications/Xcode.app"
fi
command -v git >/dev/null || fail "git is required (it comes with Xcode)."

work="$(mktemp -d -t audio-visualizer)"
trap 'rm -rf "$work"' EXIT

say "Downloading the source ($REF)"
git init -q "$work/src"
git -C "$work/src" fetch -q --depth 1 "$REPO_URL" "$REF" </dev/null
git -C "$work/src" checkout -q FETCH_HEAD

say "Building (takes a minute or two)"
# Signed ad hoc, so no Apple developer account is needed.
if ! xcodebuild \
        -project "$work/src/$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -derivedDataPath "$work/build" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
        build </dev/null >"$work/build.log" 2>&1; then
    grep -E "error:" "$work/build.log" | head -20 >&2 || tail -30 "$work/build.log" >&2
    fail "The build failed."
fi
built="$work/build/Build/Products/Release/$APP_NAME.app"
[[ -d "$built" ]] || fail "The build finished but the app wasn't found."

if pgrep -x "$APP_NAME" >/dev/null; then
    say "Quitting the running app"
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
    sleep 1
fi

target="$INSTALL_DIR/$APP_NAME.app"
say "Installing to $target"
mkdir -p "$INSTALL_DIR"
if [[ -w "$INSTALL_DIR" ]]; then
    rm -rf "$target"
    ditto "$built" "$target"
else
    sudo rm -rf "$target"
    sudo ditto "$built" "$target"
fi

say "Done. Open it from Launchpad or with:  open \"$target\""
echo "On first launch macOS asks for permission to record system audio — allow it,"
echo "otherwise the visualization won't react to sound."
