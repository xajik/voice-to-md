.PHONY: setup generate build test lint clean dmg

SCHEME = VoiceToMarkdown
CONFIGURATION = Release
BUILD_DIR = .build

setup:
	@echo "Installing xcodegen..."
	brew install xcodegen || true
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "Done. Open VoiceToMarkdown.xcodeproj in Xcode."

generate:
	xcodegen generate

build:
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		build

test:
	xcodebuild -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		test

lint:
	@if which swiftlint > /dev/null; then swiftlint; else echo "swiftlint not found, skipping"; fi

clean:
	rm -rf $(BUILD_DIR)
	rm -rf VoiceToMarkdown.xcodeproj

dmg:
	@echo "Build a signed .dmg — run via GitHub Actions release workflow."
	@echo "See .github/workflows/release.yml"
