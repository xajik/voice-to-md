.PHONY: setup generate open build build-debug test test-verbose lint lint-fix clean clean-all run deps deps-install check install uninstall dmg _sign

SCHEME        = VoiceToMarkdown
CONFIGURATION = Release
BUILD_DIR     = .build
APP_NAME      = VoiceToMarkdown.app
APP_PATH      = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(APP_NAME)
DEBUG_APP     = $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)
APP_DST       = /Applications/$(APP_NAME)
ENTITLEMENTS  = VoiceToMarkdown/Resources/VoiceToMarkdown.entitlements

# Signing identity. Ad-hoc signatures change on every build, which silently
# invalidates TCC grants (Microphone, Accessibility) — so auto-detect a stable
# "Apple Development" identity when one exists. Override with
#   make build SIGN_IDENTITY="Apple Development: Name (TEAMID)"
# or force ad-hoc with SIGN_IDENTITY=-
ifndef SIGN_IDENTITY
SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development/ {print $$2; exit}')
endif

XCB_FLAGS = -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR) \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run xcodebuild once, through xcpretty only when it is installed.
# pipefail keeps xcodebuild's exit status so failures are not masked.
define xcb
set -o pipefail 2>/dev/null; \
if command -v xcpretty >/dev/null 2>&1; then \
	xcodebuild $(1) 2>&1 | xcpretty; \
else \
	xcodebuild $(1); \
fi
endef

# ── First-time setup ─────────────────────────────────────────────────────────

setup: deps generate
	@echo ""
	@echo "  Setup complete."
	@echo "  Run 'make open' to open in Xcode, or 'make run' to build and launch."

deps:
	@echo "Checking system dependencies..."
	@command -v xcodegen > /dev/null || brew install xcodegen
	@command -v whisper-cli > /dev/null || command -v whisper-cpp > /dev/null || \
		(echo "  whisper-cli not found — install: brew install whisper-cpp" && exit 1)
	@command -v ffmpeg > /dev/null || \
		(echo "  ffmpeg not found — install: brew install ffmpeg" && exit 1)
	@echo "  All dependencies present."

# Like deps, but installs whatever is missing instead of failing.
deps-install:
	@echo "==> Checking dependencies (xcodegen, whisper-cpp, ffmpeg)…"
	@command -v xcodegen > /dev/null || brew install xcodegen
	@command -v whisper-cli > /dev/null || command -v whisper-cpp > /dev/null || brew install whisper-cpp
	@command -v ffmpeg > /dev/null || brew install ffmpeg
	@echo "    All dependencies present."

generate:
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "  VoiceToMarkdown.xcodeproj ready."

open: generate
	open VoiceToMarkdown.xcodeproj

# ── Build ─────────────────────────────────────────────────────────────────────

build:
	@$(call xcb,$(XCB_FLAGS) -configuration $(CONFIGURATION) build)
	@$(MAKE) --no-print-directory _sign APP=$(APP_PATH)

build-debug:
	@$(call xcb,$(XCB_FLAGS) -configuration Debug build)
	@$(MAKE) --no-print-directory _sign APP=$(DEBUG_APP)

# Internal: sign $(APP) with the stable identity when available, else ad-hoc.
_sign:
	@codesign --force --deep --options runtime \
		--entitlements $(ENTITLEMENTS) \
		-s "$(or $(SIGN_IDENTITY),-)" "$(APP)"
	@echo "  Signed with entitlements ($(or $(SIGN_IDENTITY),ad-hoc))."

run: build
	@echo "Launching $(APP_PATH)..."
	open "$(APP_PATH)"

# ── Test ──────────────────────────────────────────────────────────────────────

test:
	@$(call xcb,$(XCB_FLAGS) -configuration Debug -destination 'platform=macOS' test)

test-verbose:
	xcodebuild \
		$(XCB_FLAGS) \
		-configuration Debug \
		-destination 'platform=macOS' \
		test

# ── Lint ──────────────────────────────────────────────────────────────────────

lint:
	@if command -v swiftlint > /dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml 2>/dev/null || swiftlint lint; \
	else \
		echo "swiftlint not found — install: brew install swiftlint"; \
	fi

lint-fix:
	@if command -v swiftlint > /dev/null 2>&1; then \
		swiftlint lint --fix; \
	else \
		echo "swiftlint not found — install: brew install swiftlint"; \
	fi

# ── Prereq check ─────────────────────────────────────────────────────────────

check:
	@echo "=== Dependency check ==="
	@command -v xcodegen   > /dev/null && echo "  [OK] xcodegen"   || echo "  [MISSING] xcodegen   — brew install xcodegen"
	@(command -v whisper-cli > /dev/null || command -v whisper-cpp > /dev/null) \
		&& echo "  [OK] whisper"     || echo "  [MISSING] whisper    — brew install whisper-cpp"
	@command -v ffmpeg     > /dev/null && echo "  [OK] ffmpeg"     || echo "  [MISSING] ffmpeg     — brew install ffmpeg"
	@command -v swiftlint  > /dev/null && echo "  [OK] swiftlint"  || echo "  [optional] swiftlint — brew install swiftlint"
	@command -v xcpretty   > /dev/null && echo "  [OK] xcpretty"   || echo "  [optional] xcpretty  — gem install xcpretty"
	@echo ""
	@xcodebuild -version | head -1

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf $(BUILD_DIR)
	rm -rf VoiceToMarkdown.xcodeproj

clean-all: clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceToMarkdown-*

# ── Local install ─────────────────────────────────────────────────────────────
#
#   The single install flow — install.sh bootstraps (clone/update) and then
#   delegates here. Installs Homebrew deps, builds a Release .app, and copies
#   it to /Applications.
#   Usage: make install

install:
	@echo ""
	@echo "=== Voice-to-Markdown installer ==="
	@echo ""
	@[ "$$(uname -s)" = "Darwin" ] || (echo "Error: macOS only." && exit 1)
	@command -v brew > /dev/null 2>&1 \
		|| (echo "Error: Homebrew required. Install: https://brew.sh" && exit 1)
	@xcodebuild -version > /dev/null 2>&1 \
		|| (echo "Error: Xcode required (Command Line Tools alone cannot build apps)." && exit 1)
	@echo "  [OK] macOS, Homebrew, Xcode"
	@echo ""
	@$(MAKE) --no-print-directory deps-install
	@echo ""
	@echo "==> Generating Xcode project…"
	@$(MAKE) --no-print-directory generate
	@echo ""
	@echo "==> Building Release (this may take a few minutes)…"
	@$(MAKE) --no-print-directory build
	@echo ""
	@[ -d "$(APP_PATH)" ] \
		|| (echo "Error: Build finished but $(APP_PATH) was not produced." && exit 1)
	@echo "==> Installing to /Applications…"
	@if pkill -x VoiceToMarkdown 2>/dev/null; then \
		echo "    Quit running VoiceToMarkdown"; sleep 1; \
	fi
	@if [ -d "$(APP_DST)" ]; then \
		echo "    Replacing existing $(APP_DST)"; \
		rm -rf "$(APP_DST)"; \
	fi
	@cp -R "$(APP_PATH)" "$(APP_DST)"
	@echo ""
	@echo "==> Done! 🎙️"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Open VoiceToMarkdown from /Applications (menu-bar icon appears top-right)."
	@echo "  2. Grant Microphone and Accessibility access when macOS asks."
	@echo "  3. Open Settings… from the menu bar and download a Whisper model"
	@echo "     (Base, ~150 MB, is a great start)."
	@echo "  4. For Agent Mode, run any local OpenAI-compatible LLM server."
	@echo ""
	@echo "  Press ⌘⌥] anywhere to dictate. Talk. Get clean markdown. 100%% local."
	@echo ""

uninstall:
	@echo "==> Removing /Applications/$(APP_NAME)…"
	@if [ -d "$(APP_DST)" ]; then \
		rm -rf "$(APP_DST)"; \
		echo "    Removed."; \
	else \
		echo "    $(APP_DST) not found — nothing to remove."; \
	fi

# ── Distribution ─────────────────────────────────────────────────────────────

dmg:
	@echo "Release builds run via GitHub Actions on tag push."
	@echo "  git tag v1.0.0 && git push origin v1.0.0"
	@echo ""
	@echo "  Required GitHub secrets:"
	@echo "    DEVELOPER_ID_CERT_BASE64   — exported .p12 cert (base64)"
	@echo "    DEVELOPER_ID_CERT_PASSWORD — .p12 password"
	@echo "    KEYCHAIN_PASSWORD          — ephemeral keychain password"
	@echo "    APPLE_ID                   — notarization Apple ID"
	@echo "    APPLE_APP_PASSWORD         — App-specific password"
	@echo "    APPLE_TEAM_ID              — 10-char team ID"
