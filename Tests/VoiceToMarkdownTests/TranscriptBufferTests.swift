import XCTest
@testable import VoiceToMarkdown

final class TranscriptBufferTests: XCTestCase {

    // MARK: - add

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

    func testAddAtExactThresholdDoesNotFlush() async {
        let buffer = TranscriptBuffer()
        let words = Array(repeating: "word", count: 30).joined(separator: " ")
        let shouldFlush = await buffer.add(words)
        XCTAssertFalse(shouldFlush)
    }

    func testMultipleChunksAccumulate() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add(Array(repeating: "w", count: 15).joined(separator: " "))
        let shouldFlush = await buffer.add(Array(repeating: "w", count: 16).joined(separator: " "))
        XCTAssertTrue(shouldFlush)
    }

    func testAddWhileBusyGoesToPending() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        let shouldFlush = await buffer.add("goes to pending")
        XCTAssertFalse(shouldFlush, "Cannot flush while agent is busy")
        let busy = await buffer.agentBusy
        XCTAssertTrue(busy)
    }

    // MARK: - flush

    func testFlushClearsAccumulatedAndMarksBusy() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("some text here")
        let flushed = await buffer.flush()
        XCTAssertFalse(flushed.isEmpty)
        let busy = await buffer.agentBusy
        XCTAssertTrue(busy)
    }

    func testFlushJoinsMultipleChunks() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("chunk one")
        _ = await buffer.add("chunk two")
        let flushed = await buffer.flush()
        XCTAssertTrue(flushed.contains("chunk one"))
        XCTAssertTrue(flushed.contains("chunk two"))
    }

    func testFlushEmptyBufferReturnsEmptyString() async {
        let buffer = TranscriptBuffer()
        let flushed = await buffer.flush()
        XCTAssertTrue(flushed.isEmpty)
        let busy = await buffer.agentBusy
        XCTAssertTrue(busy)
    }

    // MARK: - flushAll

    func testFlushAllCombinesAccumulatedAndPending() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("accumulated")
        _ = await buffer.flush()
        _ = await buffer.add("pending")
        let all = await buffer.flushAll()
        XCTAssertTrue(all.contains("pending"))
    }

    func testFlushAllClearsEverything() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("text")
        _ = await buffer.flush()
        _ = await buffer.add("more text")
        _ = await buffer.flushAll()
        let hasPending = await buffer.hasPending()
        XCTAssertFalse(hasPending)
    }

    // MARK: - pending

    func testPendingBufferUsedWhenAgentBusy() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        _ = await buffer.add("pending text")
        let hasPending = await buffer.hasPending()
        XCTAssertTrue(hasPending)
    }

    // MARK: - agentDone

    func testAgentDonePromotesPendingBelowThreshold() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        _ = await buffer.add("few words")
        let shouldFlushNext = await buffer.agentDone()
        XCTAssertFalse(shouldFlushNext)
        let hasPending = await buffer.hasPending()
        XCTAssertTrue(hasPending)
    }

    func testAgentDonePromotesPendingAboveThresholdSignalsFlush() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        let manyWords = Array(repeating: "word", count: 31).joined(separator: " ")
        _ = await buffer.add(manyWords)
        let shouldFlush = await buffer.agentDone()
        XCTAssertTrue(shouldFlush)
    }

    func testAgentDoneWithNoPendingDoesNotSignalFlush() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        let shouldFlush = await buffer.agentDone()
        XCTAssertFalse(shouldFlush)
        let busy = await buffer.agentBusy
        XCTAssertFalse(busy)
    }

    // MARK: - clear

    func testClearResetsAllState() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.add("some text")
        await buffer.clear()
        let hasPending = await buffer.hasPending()
        XCTAssertFalse(hasPending)
        let busy = await buffer.agentBusy
        XCTAssertFalse(busy)
    }

    func testClearAfterBusyResetsBusy() async {
        let buffer = TranscriptBuffer()
        _ = await buffer.flush()
        await buffer.clear()
        let busy = await buffer.agentBusy
        XCTAssertFalse(busy)
    }

    // MARK: - full cycle

    func testFullChunkProcessCycle() async {
        let buffer = TranscriptBuffer()

        // Agent free — add chunk and flush
        _ = await buffer.add("first batch of words here")
        let text = await buffer.flush()
        XCTAssertFalse(text.isEmpty)
        let busyAfterFlush = await buffer.agentBusy
        XCTAssertTrue(busyAfterFlush)

        // Agent busy — add to pending
        _ = await buffer.add("second batch")
        let hasPending1 = await buffer.hasPending()
        XCTAssertTrue(hasPending1)

        // Agent done — pending promoted
        _ = await buffer.agentDone()
        let busyAfterDone = await buffer.agentBusy
        let hasPending2 = await buffer.hasPending()
        XCTAssertFalse(busyAfterDone)
        XCTAssertTrue(hasPending2)
    }
}
