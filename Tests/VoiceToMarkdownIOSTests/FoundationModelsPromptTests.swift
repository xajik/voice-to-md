import XCTest
@testable import VoiceToMarkdown

/// Pins the prompt/payload contract the Foundation Models backend shares with
/// the macOS HTTP backend. Pure — no Apple Intelligence required.
final class FoundationModelsPromptTests: XCTestCase {

    // MARK: - noThink prompts

    func testNoThinkPromptsHaveNoControlToken() {
        for format in OutputFormat.allCases {
            let prompts = [
                LocalLLMService.systemPrompt(for: format, noThink: false),
                LocalLLMService.editSystemPrompt(for: format, noThink: false),
                LocalLLMService.appendSystemPrompt(for: format, noThink: false)
            ]
            for prompt in prompts {
                XCTAssertFalse(prompt.contains("/no_think"))
                XCTAssertTrue(prompt.contains(format.promptExpectations),
                              "\(format.rawValue) expectations missing from prompt")
            }
        }
    }

    // MARK: - Payload parity with the macOS request bodies

    func testFormatUserPayloadMatchesMacRequestBody() throws {
        let payload = LocalLLMService.formatUserPayload(currentDocument: "# Doc", newTranscript: "hello")
        let body = LocalLLMService.buildRequestBody(
            model: "m", currentDocument: "# Doc", newTranscript: "hello", format: .md
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1]["content"], payload)
    }

    func testEditUserPayloadMatchesMacRequestBody() throws {
        let payload = LocalLLMService.editUserPayload(
            currentDocument: "# Doc", instruction: "fix", userFocus: "Doc"
        )
        let body = LocalLLMService.buildEditRequestBody(
            model: "m", currentDocument: "# Doc", instruction: "fix", userFocus: "Doc", format: .md
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1]["content"], payload)
    }

    func testAppendUserPayloadMatchesMacRequestBody() throws {
        let payload = LocalLLMService.appendUserPayload(recentContext: "Last.", newTranscript: "more")
        let body = LocalLLMService.buildAppendRequestBody(
            model: "m", recentContext: "Last.", newTranscript: "more", format: .md
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1]["content"], payload)
    }
}
