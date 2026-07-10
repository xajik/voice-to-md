import XCTest
@testable import SpeechToMarkdown

/// Drives `AgentSessionController` through its STT seam
/// (`handleFinalTranscript`) with a mock LLM — no audio, speech assets, or
/// Apple Intelligence required.
@MainActor
final class AgentSessionControllerTests: XCTestCase {
    private var tempDir: URL!
    private var mock: MockAgentLLMService!
    private var controller: AgentSessionController!
    private var savedOutputFormat: String!

    /// 31 words — one over `TranscriptBuffer.minWordsToFlush`.
    private let longUtterance = (1...31).map { "word\($0)" }.joined(separator: " ")

    override func setUp() async throws {
        savedOutputFormat = BackendSettings.shared.outputFormat
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stmd-tests-\(UUID().uuidString)")
        mock = MockAgentLLMService()
        controller = AgentSessionController(llm: mock)
        controller.outputFormat = .md
    }

    override func tearDown() async throws {
        BackendSettings.shared.outputFormat = savedOutputFormat
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Installs a live session without going through STT/asset setup.
    private func makeSession(format: OutputFormat = .md, state: SessionState = .recording) throws {
        var session = STMDSession(modelSize: .base, baseDir: tempDir, format: format)
        session.state = state
        try FileManager.default.createDirectory(at: session.dirPath, withIntermediateDirectories: true)
        controller.session = session
    }

    // MARK: - Threshold flush

    func testThirtyOneWordsTriggerExactlyOneFormatFlush() async throws {
        try makeSession()
        mock.response = "# Formatted"

        await controller.handleFinalTranscript(longUtterance)
        await controller.awaitPendingFlushes()

        XCTAssertEqual(mock.calls.count, 1)
        guard case .format(_, let transcript, let format) = mock.calls[0] else {
            return XCTFail("Expected format call, got \(mock.calls[0])")
        }
        XCTAssertEqual(transcript, longUtterance)
        XCTAssertEqual(format, .md)
        XCTAssertEqual(controller.document, "# Formatted")
        // Persisted to docPath and raw transcript appended.
        let docPath = try XCTUnwrap(controller.session?.docPath)
        XCTAssertEqual(try String(contentsOf: docPath, encoding: .utf8), "# Formatted")
        let txtPath = try XCTUnwrap(controller.session?.txtPath)
        XCTAssertTrue(try String(contentsOf: txtPath, encoding: .utf8).contains("word31"))
    }

    func testShortUtteranceDoesNotFlush() async throws {
        try makeSession()

        await controller.handleFinalTranscript("just a few words")
        await controller.awaitPendingFlushes()

        XCTAssertTrue(mock.calls.isEmpty)
        XCTAssertTrue(controller.transcript.contains("just a few words"))
    }

    // MARK: - Busy agent → pending queue → re-flush

    func testTextArrivingDuringBusyAgentReflushesAfterCompletion() async throws {
        try makeSession()
        mock.hold = true
        mock.response = "# First"

        await controller.handleFinalTranscript(longUtterance)
        // Wait until the first flush has pulled the buffer (agentBusy set).
        while mock.calls.isEmpty { await Task.yield() }

        let second = (1...31).map { "more\($0)" }.joined(separator: " ")
        await controller.handleFinalTranscript(second)
        XCTAssertEqual(mock.calls.count, 1, "second batch must queue while the agent is busy")

        mock.hold = false
        mock.release()
        await controller.awaitPendingFlushes()

        XCTAssertEqual(mock.calls.count, 2)
        guard case .format(_, let transcript, _) = mock.calls[1] else {
            return XCTFail("Expected format call, got \(mock.calls[1])")
        }
        XCTAssertEqual(transcript, second)
    }

    // MARK: - Edit mode

    func testEditModePassesSelectionAsUserFocus() async throws {
        try makeSession()
        controller.userDidEdit("# Title\nBody text")
        controller.mode = .edit
        controller.editorSelection = "Body text"
        mock.response = "# Title\nEdited body"

        await controller.handleFinalTranscript(longUtterance)
        await controller.awaitPendingFlushes()

        XCTAssertEqual(mock.calls.count, 1)
        guard case .edit(let doc, let instruction, let focus, _) = mock.calls[0] else {
            return XCTFail("Expected edit call, got \(mock.calls[0])")
        }
        XCTAssertEqual(doc, "# Title\nBody text")
        XCTAssertEqual(instruction, longUtterance)
        XCTAssertEqual(focus, "Body text")
        XCTAssertEqual(controller.document, "# Title\nEdited body")
    }

    // MARK: - Append mode

    func testAppendModeJoinsDeltaLocally() async throws {
        try makeSession()
        let existing = "One. Two. Three. Four."
        controller.userDidEdit(existing)
        controller.mode = .append
        mock.response = "- New item"

        await controller.handleFinalTranscript(longUtterance)
        await controller.awaitPendingFlushes()

        XCTAssertEqual(mock.calls.count, 1)
        guard case .append(let context, let transcript, _) = mock.calls[0] else {
            return XCTFail("Expected append call, got \(mock.calls[0])")
        }
        XCTAssertEqual(context, LocalLLMService.lastSentences(existing, count: 3))
        XCTAssertEqual(transcript, longUtterance)
        XCTAssertEqual(
            controller.document,
            LocalLLMService.joinAppended(base: existing, delta: "- New item")
        )
    }

    // MARK: - Format migration

    func testOutputFormatSwitchRenamesDocumentFile() async throws {
        try makeSession(format: .md)
        controller.userDidEdit("# Doc")
        let oldPath = try XCTUnwrap(controller.session?.docPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldPath.path))

        controller.outputFormat = .html

        let newPath = try XCTUnwrap(controller.session?.docPath)
        XCTAssertEqual(newPath.pathExtension, "html")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath.path))
        XCTAssertEqual(controller.session?.format, .html)
        XCTAssertEqual(try String(contentsOf: newPath, encoding: .utf8), "# Doc")
    }

    // MARK: - Error path

    func testLLMErrorSurfacesAndUnblocksBuffer() async throws {
        try makeSession()
        mock.error = FoundationModelsError.documentTooLarge

        await controller.handleFinalTranscript(longUtterance)
        await controller.awaitPendingFlushes()

        XCTAssertNotNil(controller.error)
        // The buffer must be unblocked: the next threshold crossing flushes again.
        mock.error = nil
        mock.response = "# Recovered"
        await controller.handleFinalTranscript(longUtterance)
        await controller.awaitPendingFlushes()
        XCTAssertEqual(controller.document, "# Recovered")
    }
}

// MARK: - Mock

/// Records calls and streams a configurable response; `hold` parks streams
/// until `release()` so tests can deterministically overlap flushes.
private final class MockAgentLLMService: AgentLLMService {
    enum Call {
        case format(currentDocument: String, newTranscript: String, format: OutputFormat)
        case edit(currentDocument: String, instruction: String, userFocus: String?, format: OutputFormat)
        case append(recentContext: String, newTranscript: String, format: OutputFormat)
    }

    private(set) var calls: [Call] = []
    var response = "response"
    var error: Error?
    var hold = false
    private var heldContinuations: [AsyncThrowingStream<String, Error>.Continuation] = []

    func release() {
        let response = self.response
        heldContinuations.forEach {
            $0.yield(response)
            $0.finish()
        }
        heldContinuations.removeAll()
    }

    func formatTranscript(
        currentDocument: String, newTranscript: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        calls.append(.format(currentDocument: currentDocument, newTranscript: newTranscript, format: format))
        return makeStream()
    }

    func editDocument(
        currentDocument: String, instruction: String, userFocus: String?, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        calls.append(.edit(
            currentDocument: currentDocument, instruction: instruction, userFocus: userFocus, format: format
        ))
        return makeStream()
    }

    func appendTranscript(
        recentContext: String, newTranscript: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        calls.append(.append(recentContext: recentContext, newTranscript: newTranscript, format: format))
        return makeStream()
    }

    private func makeStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
            } else if hold {
                heldContinuations.append(continuation)
            } else {
                continuation.yield(response)
                continuation.finish()
            }
        }
    }
}
