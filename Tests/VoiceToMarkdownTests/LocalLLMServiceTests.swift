import XCTest
@testable import VoiceToMarkdown

final class LocalLLMServiceTests: XCTestCase {

    // MARK: - Models list decoding

    func testModelListDecoding() throws {
        let json = """
        {"object":"list","data":[{"id":"model-a","object":"model","created":1,"owned_by":"omlx"},{"id":"model-b","object":"model","created":2,"owned_by":"omlx"}]}
        """
        let list = try JSONDecoder().decode(LocalLLMService.ModelList.self, from: Data(json.utf8))
        XCTAssertEqual(list.data.map(\.id), ["model-a", "model-b"])
    }

    // MARK: - Request body

    func testBuildRequestBodyStructure() throws {
        let body = LocalLLMService.buildRequestBody(
            model: "test-model",
            currentMarkdown: "# Doc",
            newTranscript: "hello world"
        )
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["stream"] as? Bool, true)

        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1]["role"], "user")

        let userContent = try XCTUnwrap(messages[1]["content"])
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(userContent.utf8)) as? [String: String]
        )
        XCTAssertEqual(payload["current_markdown"], "# Doc")
        XCTAssertEqual(payload["new_transcript"], "hello world")
    }

    func testRequestBodyIsSerializable() {
        let body = LocalLLMService.buildRequestBody(model: "m", currentMarkdown: "", newTranscript: "text")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - SSE parsing

    func testParseSSELineExtractsDelta() {
        let line = #"data: {"id":"c1","choices":[{"index":0,"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(LocalLLMService.parseSSELine(line), "Hello")
    }

    func testParseSSELineIgnoresDone() {
        XCTAssertNil(LocalLLMService.parseSSELine("data: [DONE]"))
    }

    func testParseSSELineIgnoresNonDataLines() {
        XCTAssertNil(LocalLLMService.parseSSELine(""))
        XCTAssertNil(LocalLLMService.parseSSELine(": keepalive"))
        XCTAssertNil(LocalLLMService.parseSSELine("event: ping"))
    }

    func testParseSSELineIgnoresEmptyDelta() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        XCTAssertNil(LocalLLMService.parseSSELine(line))
    }

    // MARK: - Output cleaning

    func testCleanOutputStripsThinkBlock() {
        let raw = "<think>reasoning here</think># Title\n\nContent"
        XCTAssertEqual(LocalLLMService.cleanOutput(raw), "# Title\n\nContent")
    }

    func testCleanOutputHidesUnterminatedThink() {
        // Mid-stream: <think> opened but not yet closed — show nothing after it
        let raw = "<think>still reasoning"
        XCTAssertEqual(LocalLLMService.cleanOutput(raw), "")
    }

    func testCleanOutputStripsCodeFences() {
        let raw = "```markdown\n# Title\n\nContent\n```"
        XCTAssertEqual(LocalLLMService.cleanOutput(raw), "# Title\n\nContent")
    }

    func testCleanOutputPassesPlainMarkdownThrough() {
        let raw = "# Title\n\n- a bullet\n- another"
        XCTAssertEqual(LocalLLMService.cleanOutput(raw), raw)
    }

    func testCleanOutputTrimsWhitespace() {
        XCTAssertEqual(LocalLLMService.cleanOutput("\n\n# T\n\n"), "# T")
    }

    func testCleanOutputMultipleThinkBlocks() {
        let raw = "<think>a</think>First<think>b</think> Second"
        XCTAssertEqual(LocalLLMService.cleanOutput(raw), "First Second")
    }
}
