#!/usr/bin/env bash
#
# Voice-to-Markdown installer
#   curl -fsSL https://raw.githubusercontent.com/xajik/voice-to-md/main/install.sh | bash
#
# Installs build dependencies with Homebrew, builds the app from source,
# and copies it to /Applications.
#
# The build is ad-hoc signed, which is fine for personal use. Note that
# re-running this installer produces a new signature, so macOS will ask
# for Microphone / Accessibility permission again after an update.

set -euo pipefail

REPO_URL="https://github.com/xajik/voice-to-md.git"
BUILD_DIR="${VTMD_BUILD_DIR:-$HOME/.vtmd/src}"
APP_NAME="VoiceToMarkdown.app"
APP_SRC=".build/Build/Products/Release/$APP_NAME"
APP_DST="/Applications/$APP_NAME"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Voice-to-Markdown is a macOS app; this installer only runs on macOS."

command -v brew >/dev/null 2>&1 \
  || fail "Homebrew is required. Install it first: https://brew.sh"

xcode-select -p >/dev/null 2>&1 \
  || fail "Xcode Command Line Tools are required. Run: xcode-select --install"

info "Installing dependencies (xcodegen, whisper-cpp, ffmpeg)…"
for pkg in xcodegen whisper-cpp ffmpeg; do
  if brew list "$pkg" >/dev/null 2>&1; then
    echo "    $pkg already installed"
  else
    brew install "$pkg"
  fi
done

if [ -d "$BUILD_DIR/.git" ]; then
  info "Updating existing checkout in $BUILD_DIR…"
  git -C "$BUILD_DIR" pull --ff-only
else
  info "Cloning $REPO_URL into $BUILD_DIR…"
  mkdir -p "$(dirname "$BUILD_DIR")"
  git clone --depth 1 "$REPO_URL" "$BUILD_DIR"
fi

info "Building (this can take a few minutes)…"
cd "$BUILD_DIR"
make setup
make build

[ -d "$APP_SRC" ] || fail "Build finished but $APP_SRC was not produced."

info "Installing to /Applications…"
if [ -d "$APP_DST" ]; then
  echo "    Replacing existing $APP_DST"
  rm -rf "$APP_DST"
fi
cp -R "$APP_SRC" "$APP_DST"

info "Done! 🎙️"
cat <<'NEXT'

Next steps:
  1. Open VoiceToMarkdown from /Applications (menu-bar icon appears top-right).
  2. Grant Microphone and Accessibility access when macOS asks.
  3. Open Settings… from the menu bar and download a Whisper model
     (Base, ~150 MB, is a great start).
  4. For Agent Mode, run any local OpenAI-compatible LLM server, e.g.:
       brew install omlx && omlx serve <model>        # default port 8000
     or Ollama / LM Studio / llama.cpp — pick the endpoint in Settings.

Press ⌘⌥] anywhere to dictate. Talk. Get clean markdown. 100% local.
NEXT
