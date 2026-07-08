import XCTest
@testable import VoiceToMarkdown

final class VTMDSessionTests: XCTestCase {
    private var baseDir: URL!

    override func setUp() {
        super.setUp()
        baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeSession(model: ModelSize = .base) -> VTMDSession {
        VTMDSession(modelSize: model, baseDir: baseDir)
    }

    // MARK: - id

    func testIdIsNumericTimestamp() {
        let session = makeSession()
        XCTAssertNotNil(Int(session.id), "id should be a numeric unix_ms timestamp")
    }

    func testIdTimestampIsReasonable() {
        let session = makeSession()
        let ms = Int(session.id)!
        let seconds = ms / 1000
        let now = Int(Date().timeIntervalSince1970)
        XCTAssertTrue(abs(now - seconds) < 5, "id timestamp should be close to now")
    }

    func testTwoSessionsHaveDistinctIds() {
        let s1 = makeSession()
        Thread.sleep(forTimeInterval: 0.002)
        let s2 = makeSession()
        XCTAssertNotEqual(s1.id, s2.id)
    }

    // MARK: - dirPath

    func testDirPathContainsVoiceToMarkdown() {
        let session = makeSession()
        XCTAssertTrue(session.dirPath.path.contains("voice-to-markdown"))
    }

    func testDirPathContainsId() {
        let session = makeSession()
        XCTAssertTrue(session.dirPath.path.contains(session.id))
    }

    func testDirPathIsUnderBaseDir() {
        let session = makeSession()
        XCTAssertTrue(session.dirPath.path.hasPrefix(baseDir.path))
    }

    // MARK: - txtPath / mdPath

    func testTxtPathExtension() {
        let session = makeSession()
        XCTAssertEqual(session.txtPath.pathExtension, "txt")
    }

    func testMdPathExtension() {
        let session = makeSession()
        XCTAssertEqual(session.mdPath.pathExtension, "md")
    }

    func testTxtPathContainsId() {
        let session = makeSession()
        XCTAssertTrue(session.txtPath.lastPathComponent.contains(session.id))
    }

    func testMdPathContainsId() {
        let session = makeSession()
        XCTAssertTrue(session.mdPath.lastPathComponent.contains(session.id))
    }

    func testTxtAndMdPathShareDirectory() {
        let session = makeSession()
        XCTAssertEqual(session.txtPath.deletingLastPathComponent(), session.mdPath.deletingLastPathComponent())
    }

    // MARK: - initial state

    func testInitialStateIsIdle() {
        let session = makeSession()
        XCTAssertEqual(session.state, .idle)
    }

    // MARK: - modelSize

    func testModelSizePreserved() {
        let session = makeSession(model: .small)
        XCTAssertEqual(session.modelSize, .small)
    }

    // MARK: - mutability

    func testStateIsMutable() {
        var session = makeSession()
        session.state = .recording
        XCTAssertEqual(session.state, .recording)
    }
}
