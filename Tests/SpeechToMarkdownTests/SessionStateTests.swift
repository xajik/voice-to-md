import XCTest
@testable import SpeechToMarkdown

final class SessionStateTests: XCTestCase {

    // MARK: - displayName

    func testDisplayNamesAreNonEmpty() {
        for state in allStates {
            XCTAssertFalse(state.displayName.isEmpty, "\(state) has empty displayName")
        }
    }

    func testDisplayNameValues() {
        XCTAssertEqual(SessionState.idle.displayName, "Idle")
        XCTAssertEqual(SessionState.initializing.displayName, "Starting...")
        XCTAssertEqual(SessionState.recording.displayName, "Recording")
        XCTAssertEqual(SessionState.processing.displayName, "Processing")
        XCTAssertEqual(SessionState.paused.displayName, "Paused")
    }

    // MARK: - isActive

    func testActiveStates() {
        XCTAssertTrue(SessionState.recording.isActive)
        XCTAssertTrue(SessionState.processing.isActive)
        XCTAssertTrue(SessionState.paused.isActive)
    }

    func testInactiveStates() {
        XCTAssertFalse(SessionState.idle.isActive)
        XCTAssertFalse(SessionState.initializing.isActive)
    }

    // MARK: - canRecord

    func testCanRecordFromPaused() {
        XCTAssertTrue(SessionState.paused.canRecord)
    }

    func testCannotRecordFromOtherStates() {
        let blocked: [SessionState] = [.idle, .initializing, .recording, .processing]
        for state in blocked {
            XCTAssertFalse(state.canRecord, "\(state) should not allow recording")
        }
    }

    // MARK: - canPause

    func testCanPauseOnlyFromRecording() {
        XCTAssertTrue(SessionState.recording.canPause)
        let others: [SessionState] = [.idle, .initializing, .processing, .paused]
        for state in others {
            XCTAssertFalse(state.canPause, "\(state) should not allow pause")
        }
    }

    // MARK: - canStop

    func testCanStopFromActiveStates() {
        XCTAssertTrue(SessionState.recording.canStop)
        XCTAssertTrue(SessionState.processing.canStop)
        XCTAssertTrue(SessionState.paused.canStop)
    }

    func testCannotStopFromTerminalOrPendingStates() {
        XCTAssertFalse(SessionState.idle.canStop)
        XCTAssertFalse(SessionState.initializing.canStop)
    }

    // MARK: - Equatable

    func testSameStateIsEqual() {
        XCTAssertEqual(SessionState.recording, SessionState.recording)
    }

    func testDifferentStatesAreNotEqual() {
        XCTAssertNotEqual(SessionState.recording, SessionState.paused)
    }

    // MARK: - Helpers

    private var allStates: [SessionState] {
        [.idle, .initializing, .recording, .processing, .paused]
    }
}
