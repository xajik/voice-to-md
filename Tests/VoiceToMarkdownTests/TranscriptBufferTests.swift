import XCTest
@testable import VoiceToMarkdown

final class TranscriptBufferTests: XCTestCase {
    func testAddBelowThresholdDoesNotFlush() async {
        let buffer = TranscriptBuffer()
        let shouldFlush = await buffer.add("hello world")
        XCTAssertFalse(shouldFlush)
    }

    func testAddExceedingThresholdTriggersFlush() async {
        let buffer = TranscriptBuffer()
        let words = Array(repeating: "word", count: 31).joined(separator: " ")
        let shouldFlush = await buffer.add(words)
        XCTAssertTrue(shouldFlush)
    }

    func testFlushClearsAccumulatedAndMarksBusy() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("some text here")
        let flushed = await buffer.flush()
        XCTAssertFalse(flushed.isEmpty)
        let busy = await buffer.agentBusy
        XCTAssertTrue(busy)
    }

    func testPendingBufferUsedWhenAgentBusy() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        _ = await buffer.add("pending text")
        let hasPending = await buffer.hasPending()
        XCTAssertTrue(hasPending)
    }

    func testAgentDonePromotesPending() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        _ = await buffer.add("pending chunk")
        let shouldFlushNext = await buffer.agentDone()
        XCTAssertFalse(shouldFlushNext)
        let hasPending = await buffer.hasPending()
        XCTAssertTrue(hasPending)
    }

    func testClearResetsAllState() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("some text")
        await buffer.clear()
        let hasPending = await buffer.hasPending()
        XCTAssertFalse(hasPending)
        let busy = await buffer.agentBusy
        XCTAssertFalse(busy)
    }
}
