import XCTest
@testable import VoiceToMarkdown

final class VTMDFileManagerTests: XCTestCase {
    private var tmpDir: URL!
    private var fm: VTMDFileManager { VTMDFileManager.shared }

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - appendTranscript

    func testAppendTranscriptCreatesFile() throws {
        let file = tmpDir.appendingPathComponent("test.txt")
        try fm.appendTranscript("hello", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("hello"))
    }

    func testAppendTranscriptAppendsMultipleLines() throws {
        let file = tmpDir.appendingPathComponent("multi.txt")
        try fm.appendTranscript("line 1", to: file)
        try fm.appendTranscript("line 2", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("line 1"))
        XCTAssertTrue(content.contains("line 2"))
    }

    func testAppendTranscriptAddsNewline() throws {
        let file = tmpDir.appendingPathComponent("newline.txt")
        try fm.appendTranscript("entry", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.hasSuffix("\n"))
    }

    func testAppendTranscriptPreservesOrder() throws {
        let file = tmpDir.appendingPathComponent("order.txt")
        try fm.appendTranscript("alpha", to: file)
        try fm.appendTranscript("beta", to: file)
        try fm.appendTranscript("gamma", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        let alphaIdx = content.range(of: "alpha")!.lowerBound
        let betaIdx = content.range(of: "beta")!.lowerBound
        let gammaIdx = content.range(of: "gamma")!.lowerBound
        XCTAssertTrue(alphaIdx < betaIdx && betaIdx < gammaIdx)
    }

    // MARK: - writeMarkdown / readMarkdown

    func testWriteAndReadMarkdown() throws {
        let file = tmpDir.appendingPathComponent("note.md")
        let expected = "# Hello\n\nSome **bold** text."
        try fm.writeMarkdown(expected, to: file)
        XCTAssertEqual(fm.readMarkdown(from: file), expected)
    }

    func testWriteMarkdownOverwritesPreviousContent() throws {
        let file = tmpDir.appendingPathComponent("overwrite.md")
        try fm.writeMarkdown("first version", to: file)
        try fm.writeMarkdown("second version", to: file)
        XCTAssertEqual(fm.readMarkdown(from: file), "second version")
    }

    func testReadMarkdownReturnsEmptyForMissingFile() {
        let file = tmpDir.appendingPathComponent("nonexistent.md")
        XCTAssertEqual(fm.readMarkdown(from: file), "")
    }

    func testRoundTripUnicodeContent() throws {
        let file = tmpDir.appendingPathComponent("unicode.md")
        let content = "# 日本語\n\nEmoji: 🎙️🤖"
        try fm.writeMarkdown(content, to: file)
        XCTAssertEqual(fm.readMarkdown(from: file), content)
    }

    // MARK: - isModelDownloaded

    func testIsModelDownloadedReturnsFalseForMissing() {
        XCTAssertFalse(fm.isModelDownloaded(.large))
    }

    // MARK: - listSessions

    private func makeSessionDir(id: String, txt: String? = "raw transcript", doc: (ext: String, content: String)? = nil) {
        let dir = tmpDir.appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let txt {
            try? txt.write(to: dir.appendingPathComponent("\(id).txt"), atomically: true, encoding: .utf8)
        }
        if let doc {
            try? doc.content.write(to: dir.appendingPathComponent("\(id).\(doc.ext)"), atomically: true, encoding: .utf8)
        }
    }

    func testListSessionsEmptyForEmptyDirectory() {
        XCTAssertTrue(VTMDFileManager.listSessions(in: tmpDir).isEmpty)
    }

    func testListSessionsDetectsTxtFormatWhenOnlyTxtFilePresent() {
        makeSessionDir(id: "1000")
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        XCTAssertEqual(sessions.first?.format, .txt)
    }

    func testListSessionsDetectsMdFormat() {
        makeSessionDir(id: "2000", doc: (ext: "md", content: "# Notes"))
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        XCTAssertEqual(sessions.first?.format, .md)
    }

    func testListSessionsDetectsHtmlFormat() {
        makeSessionDir(id: "3000", doc: (ext: "html", content: "<h2>Notes</h2>"))
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        XCTAssertEqual(sessions.first?.format, .html)
    }

    func testListSessionsSortedNewestFirst() {
        makeSessionDir(id: "1000")
        makeSessionDir(id: "3000")
        makeSessionDir(id: "2000")
        let ids = VTMDFileManager.listSessions(in: tmpDir).map(\.id)
        XCTAssertEqual(ids, ["3000", "2000", "1000"])
    }

    func testListSessionsSkipsNonNumericDirectoryNames() {
        makeSessionDir(id: "1000")
        try? FileManager.default.createDirectory(
            at: tmpDir.appendingPathComponent("not-a-session"), withIntermediateDirectories: true
        )
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "1000")
    }

    func testListSessionsPreviewStripsMarkdownHeadingMarker() {
        makeSessionDir(id: "1000", doc: (ext: "md", content: "# Hello World\n\nBody text"))
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        XCTAssertEqual(sessions.first?.preview, "Hello World")
    }

    func testListSessionsPreviewEmptyForEmptyDocument() {
        makeSessionDir(id: "1000", txt: "")
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        XCTAssertEqual(sessions.first?.preview, "")
    }

    func testListSessionsDirPathMatchesSessionDirectory() {
        makeSessionDir(id: "1000")
        let sessions = VTMDFileManager.listSessions(in: tmpDir)
        // /tmp resolves through a /private symlink on macOS, so compare the
        // path tail rather than requiring byte-for-byte URL equality.
        XCTAssertEqual(sessions.first?.dirPath.lastPathComponent, "1000")
        XCTAssertTrue(sessions.first?.dirPath.path.hasSuffix("/1000") ?? false)
    }
}
