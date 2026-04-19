import XCTest
@testable import VoiceToMarkdown

final class ProviderRegistryTests: XCTestCase {
    func testDetectsClaude() {
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

    func testOverrideWinsOverCommand() {
        let provider = ProviderRegistry.shared.detect(from: "claude", override: "gemini")
        XCTAssertEqual(provider.name, "gemini")
    }

    func testOpenCodeThrowsOnSetupVoice() {
        let provider = OpenCodeProvider()
        XCTAssertThrowsError(try provider.setupVoice(workDir: "/tmp", hooksPort: 7070))
    }

    func testCodexThrowsOnSetupVoice() {
        let provider = CodexProvider()
        XCTAssertThrowsError(try provider.setupVoice(workDir: "/tmp", hooksPort: 7070))
    }
}
