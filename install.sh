#!/usr/bin/env bash
#
# Voice-to-Markdown installer
#   curl -fsSL https://raw.githubusercontent.com/xajik/voice-to-md/main/install.sh | bash
#
# Bootstraps a source checkout and delegates the actual work (dependencies,
# build, copy to /Applications) to `make install`.
#
# Signing: `make install` auto-detects an "Apple Development" identity so
# repeat installs keep their Microphone / Accessibility grants. Without one,
# the build is ad-hoc signed and macOS will re-ask for permissions after an
# update.

set -euo pipefail

REPO_URL="https://github.com/xajik/voice-to-md.git"
BUILD_DIR="${VTMD_BUILD_DIR:-$HOME/.vtmd/src}"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Voice-to-Markdown is a macOS app; this installer only runs on macOS."

command -v brew >/dev/null 2>&1 \
  || fail "Homebrew is required. Install it first: https://brew.sh"

xcodebuild -version >/dev/null 2>&1 \
  || fail "Xcode is required (Command Line Tools alone cannot build apps). Install it from the App Store."

if [ -d "$BUILD_DIR/.git" ]; then
  info "Updating existing checkout in $BUILD_DIR…"
  git -C "$BUILD_DIR" fetch --depth 1 origin main
  git -C "$BUILD_DIR" reset --hard origin/main
else
  info "Cloning $REPO_URL into $BUILD_DIR…"
  mkdir -p "$(dirname "$BUILD_DIR")"
  git clone --depth 1 "$REPO_URL" "$BUILD_DIR"
fi

exec make -C "$BUILD_DIR" install
