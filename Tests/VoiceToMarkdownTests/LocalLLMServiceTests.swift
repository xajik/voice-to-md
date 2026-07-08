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

    func testBuildEditRequestBodyStructure() throws {
        let body = LocalLLMService.buildEditRequestBody(
            model: "test-model",
            currentMarkdown: "# Doc",
            instruction: "change the title",
            userFocus: "# Doc"
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[0]["content"], LocalLLMService.editSystemPrompt)

        let userContent = try XCTUnwrap(messages[1]["content"])
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(userContent.utf8)) as? [String: String]
        )
        XCTAssertEqual(payload["current_markdown"], "# Doc")
        XCTAssertEqual(payload["new_transcript"], "change the title")
        XCTAssertEqual(payload["user_focus"], "# Doc")
    }

    func testBuildEditRequestBodyOmitsFocusWhenAbsent() throws {
        for focus in [nil, ""] {
            let body = LocalLLMService.buildEditRequestBody(
                model: "m", currentMarkdown: "# Doc", instruction: "fix it", userFocus: focus
            )
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let userContent = try XCTUnwrap(messages[1]["content"])
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(userContent.utf8)) as? [String: String]
            )
            XCTAssertNil(payload["user_focus"])
        }
    }

    func testBuildAppendRequestBodyStructure() throws {
        let body = LocalLLMService.buildAppendRequestBody(
            model: "test-model",
            recentContext: "Last sentence.",
            newTranscript: "more words"
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[0]["content"], LocalLLMService.appendSystemPrompt)

        let userContent = try XCTUnwrap(messages[1]["content"])
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(userContent.utf8)) as? [String: String]
        )
        XCTAssertEqual(payload["recent_context"], "Last sentence.")
        XCTAssertEqual(payload["new_transcript"], "more words")
        XCTAssertNil(payload["current_markdown"])
    }

    // MARK: - lastSentences

    func testLastSentencesTakesSuffix() {
        let text = "One. Two! Three? Four. Five."
        XCTAssertEqual(LocalLLMService.lastSentences(text, count: 3), "Three? Four. Five.")
    }

    func testLastSentencesReturnsWholeTextWhenFewer() {
        XCTAssertEqual(LocalLLMService.lastSentences("Only one.", count: 3), "Only one.")
    }

    func testLastSentencesEmptyText() {
        XCTAssertEqual(LocalLLMService.lastSentences("", count: 3), "")
        XCTAssertEqual(LocalLLMService.lastSentences("   \n ", count: 3), "")
    }

    func testLastSentencesTreatsNewlineAsBoundary() {
        let text = "# Heading\nFirst line prose. Second sentence."
        XCTAssertEqual(LocalLLMService.lastSentences(text, count: 2), "First line prose. Second sentence.")
    }

    func testLastSentencesHandlesMissingTerminalPunctuation() {
        let text = "One. Two. Three with no period"
        XCTAssertEqual(LocalLLMService.lastSentences(text, count: 2), "Two. Three with no period")
    }

    // MARK: - joinAppended

    func testJoinAppendedEmptyBase() {
        XCTAssertEqual(LocalLLMService.joinAppended(base: "", delta: "New text."), "New text.")
    }

    func testJoinAppendedEmptyDelta() {
        XCTAssertEqual(LocalLLMService.joinAppended(base: "# Doc", delta: "  \n"), "# Doc")
    }

    func testJoinAppendedProseContinuesInline() {
        XCTAssertEqual(
            LocalLLMService.joinAppended(base: "First sentence.", delta: "Second sentence."),
            "First sentence. Second sentence."
        )
    }

    func testJoinAppendedBlockStartsNewParagraph() {
        XCTAssertEqual(
            LocalLLMService.joinAppended(base: "Prose.", delta: "## Section"),
            "Prose.\n\n## Section"
        )
        XCTAssertEqual(
            LocalLLMService.joinAppended(base: "Prose.", delta: "- bullet"),
            "Prose.\n\n- bullet"
        )
        XCTAssertEqual(
            LocalLLMService.joinAppended(base: "Prose.", delta: "1. first item"),
            "Prose.\n\n1. first item"
        )
    }

    func testJoinAppendedTrimsBaseTrailingWhitespace() {
        XCTAssertEqual(
            LocalLLMService.joinAppended(base: "Prose.\n\n", delta: "More prose."),
            "Prose. More prose."
        )
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
