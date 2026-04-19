.PHONY: setup generate open build test lint clean run deps check

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
	@which tmux > /dev/null || \
		(echo "  tmux not found — install: brew install tmux" && exit 1)
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

build-debug:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		build 2>&1 | xcpretty || true

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
	@which tmux       > /dev/null && echo "  [OK] tmux"       || echo "  [MISSING] tmux       — brew install tmux"
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
