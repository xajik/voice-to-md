.PHONY: setup generate open build test lint clean run deps check install uninstall

SCHEME        = VoiceToMarkdown
CONFIGURATION = Release
BUILD_DIR     = .build
APP_PATH      = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/VoiceToMarkdown.app

# ── First-time setup ─────────────────────────────────────────────────────────

setup: deps generate
	@echo ""
	@echo "  Setup complete."
	@echo "  Run 'make open' to open in Xcode, or 'make run' to build and launch."

deps:
	@echo "Checking system dependencies..."
	@which xcodegen > /dev/null || brew install xcodegen
	@which whisper-cli > /dev/null || which whisper-cpp > /dev/null || \
		(echo "  whisper-cli not found — install: brew install whisper-cpp" && exit 1)
	@which ffmpeg > /dev/null || \
		(echo "  ffmpeg not found — install: brew install ffmpeg" && exit 1)
	@echo "  All dependencies present."

generate:
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "  VoiceToMarkdown.xcodeproj ready."

open: generate
	open VoiceToMarkdown.xcodeproj

# ── Build ─────────────────────────────────────────────────────────────────────

build:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		build 2>&1 | xcpretty || xcodebuild \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		build
	@codesign --force --deep \
		--entitlements VoiceToMarkdown/Resources/VoiceToMarkdown.entitlements \
		-s - \
		"$(APP_PATH)" 2>/dev/null; \
	if [ $$? -eq 0 ]; then \
		echo "  Signed with entitlements."; \
	fi

build-debug:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		build 2>&1 | xcpretty || true
	@if [ -d "$(BUILD_DIR)/Build/Products/Debug/VoiceToMarkdown.app" ]; then \
		echo "  Signing with entitlements..."; \
		codesign --force --deep \
			--entitlements VoiceToMarkdown/Resources/VoiceToMarkdown.entitlements \
			-s - \
			"$(BUILD_DIR)/Build/Products/Debug/VoiceToMarkdown.app"; \
	fi

run: build
	@echo "Launching $(APP_PATH)..."
	open "$(APP_PATH)"

# ── Test ──────────────────────────────────────────────────────────────────────

test:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		test 2>&1 | xcpretty || xcodebuild \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		test

test-verbose:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		test

# ── Lint ──────────────────────────────────────────────────────────────────────

lint:
	@if which swiftlint > /dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml 2>/dev/null || swiftlint lint; \
	else \
		echo "swiftlint not found — install: brew install swiftlint"; \
	fi

lint-fix:
	@if which swiftlint > /dev/null 2>&1; then \
		swiftlint lint --fix; \
	else \
		echo "swiftlint not found — install: brew install swiftlint"; \
	fi

# ── Prereq check ─────────────────────────────────────────────────────────────

check:
	@echo "=== Dependency check ==="
	@which xcodegen   > /dev/null && echo "  [OK] xcodegen"   || echo "  [MISSING] xcodegen   — brew install xcodegen"
	@(which whisper-cli > /dev/null || which whisper-cpp > /dev/null) \
		&& echo "  [OK] whisper"     || echo "  [MISSING] whisper    — brew install whisper-cpp"
	@which ffmpeg     > /dev/null && echo "  [OK] ffmpeg"     || echo "  [MISSING] ffmpeg     — brew install ffmpeg"
	@which swiftlint  > /dev/null && echo "  [OK] swiftlint"  || echo "  [optional] swiftlint — brew install swiftlint"
	@which xcpretty   > /dev/null && echo "  [OK] xcpretty"   || echo "  [optional] xcpretty  — gem install xcpretty"
	@echo ""
	@xcodebuild -version | head -1

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf $(BUILD_DIR)
	rm -rf VoiceToMarkdown.xcodeproj

clean-all: clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceToMarkdown-*

# ── Local install (mirrors install.sh for personal use) ──────────────────────
#
#   Replicates the production install.sh flow without cloning the repo.
#   Installs Homebrew deps, builds a Release .app, and copies it to /Applications.
#   Usage: make install

APP_NAME      = VoiceToMarkdown.app
APP_DST       = /Applications/$(APP_NAME)

install:
	@echo ""
	@echo "=== Voice-to-Markdown local installer ==="
	@echo ""
	@# ── Pre-flight checks ────────────────────────────────────────────────
	@[ "$$(uname -s)" = "Darwin" ] || (echo "Error: macOS only." && exit 1)
	@command -v brew > /dev/null 2>&1 \
		|| (echo "Error: Homebrew required. Install: https://brew.sh" && exit 1)
	@xcode-select -p > /dev/null 2>&1 \
		|| (echo "Error: Xcode CLT required. Run: xcode-select --install" && exit 1)
	@echo "  [OK] macOS, Homebrew, Xcode CLT"
	@echo ""
	@# ── Install Homebrew dependencies ────────────────────────────────────
	@echo "==> Installing dependencies (xcodegen, whisper-cpp, ffmpeg)…"
	@for pkg in xcodegen whisper-cpp ffmpeg; do \
		if brew list "$$pkg" > /dev/null 2>&1; then \
			echo "    $$pkg already installed"; \
		else \
			echo "    Installing $$pkg…"; \
			brew install "$$pkg"; \
		fi; \
	done
	@echo ""
	@# ── Generate project & build ──────────────────────────────────────────
	@echo "==> Generating Xcode project…"
	@$(MAKE) generate
	@echo ""
	@echo "==> Building Release (this may take a few minutes)…"
	@$(MAKE) build
	@echo ""
	@# ── Copy .app to /Applications ───────────────────────────────────────
	@[ -d "$(APP_PATH)" ] \
		|| (echo "Error: Build finished but $(APP_PATH) was not produced." && exit 1)
	@echo "==> Installing to /Applications…"
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
