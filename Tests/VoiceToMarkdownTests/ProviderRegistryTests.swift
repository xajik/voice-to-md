import XCTest
@testable import VoiceToMarkdown

final class ProviderRegistryTests: XCTestCase {

    // MARK: - Detection by command string

    func testDetectsClaudeByAlias() {
        let provider = ProviderRegistry.shared.detect(from: "claude --dangerously-skip-permissions")
        XCTAssertEqual(provider.name, "claude-code")
        XCTAssertTrue(provider.supportsVoiceHooks)
    }

    func testDetectsClaudeCode() {
        let provider = ProviderRegistry.shared.detect(from: "claude-code")
        XCTAssertEqual(provider.name, "claude-code")
    }

    func testDetectsGemini() {
        let provider = ProviderRegistry.shared.detect(from: "gemini --model gemini-2.0")
        XCTAssertEqual(provider.name, "gemini")
        XCTAssertTrue(provider.supportsVoiceHooks)
    }

    func testDetectsOpenCode() {
        let provider = ProviderRegistry.shared.detect(from: "opencode")
        XCTAssertEqual(provider.name, "opencode")
        XCTAssertFalse(provider.supportsVoiceHooks)
    }

    func testDetectsCodex() {
        let provider = ProviderRegistry.shared.detect(from: "codex")
        XCTAssertEqual(provider.name, "codex")
        XCTAssertFalse(provider.supportsVoiceHooks)
    }

    func testFallsBackToClaudeForUnknown() {
        let provider = ProviderRegistry.shared.detect(from: "some-unknown-tool")
        XCTAssertEqual(provider.name, "claude-code")
    }

    func testDetectsFromAbsolutePath() {
        let provider = ProviderRegistry.shared.detect(from: "/usr/local/bin/gemini --yolo")
        XCTAssertEqual(provider.name, "gemini")
    }

    // MARK: - Override

    func testOverrideWinsOverCommand() {
        let provider = ProviderRegistry.shared.detect(from: "claude", override: "gemini")
        XCTAssertEqual(provider.name, "gemini")
    }

    func testOverrideIsCaseInsensitive() {
        let provider = ProviderRegistry.shared.detect(from: "claude", override: "GEMINI")
        XCTAssertEqual(provider.name, "gemini")
    }

    func testUnknownOverrideFallsBackToCommand() {
        let provider = ProviderRegistry.shared.detect(from: "gemini", override: "nonexistent")
        XCTAssertEqual(provider.name, "claude-code", "Unknown override falls back to command-based detection which also falls back to claude")
    }

    // MARK: - Voice hook support

    func testOpenCodeDoesNotSupportVoiceHooks() {
        let provider = OpenCodeProvider()
        XCTAssertFalse(provider.supportsVoiceHooks)
        XCTAssertThrowsError(try provider.setupVoice(workDir: "/tmp", hooksPort: 7070))
    }

    func testCodexDoesNotSupportVoiceHooks() {
        let provider = CodexProvider()
        XCTAssertFalse(provider.supportsVoiceHooks)
        XCTAssertThrowsError(try provider.setupVoice(workDir: "/tmp", hooksPort: 7070))
    }

    func testVoiceHookErrorIsNotSupported() {
        let provider = OpenCodeProvider()
        XCTAssertThrowsError(try provider.setupVoice(workDir: "/tmp", hooksPort: 7070)) { error in
            guard let providerError = error as? ProviderError else {
                XCTFail("Expected ProviderError")
                return
            }
            if case .notSupported = providerError { } else {
                XCTFail("Expected notSupported error")
            }
        }
    }
}
