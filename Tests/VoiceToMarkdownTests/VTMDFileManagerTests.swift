import XCTest
@testable import VoiceToMarkdown

final class VTMDFileManagerTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testAppendTranscriptCreatesFile() throws {
        let file = tmpDir.appendingPathComponent("test.txt")
        let fm = VTMDFileManager.shared
        try fm.appendTranscript("hello", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("hello"))
    }

    func testAppendTranscriptAppendsMultipleLines() throws {
        let file = tmpDir.appendingPathComponent("multi.txt")
        let fm = VTMDFileManager.shared
        try fm.appendTranscript("line 1", to: file)
        try fm.appendTranscript("line 2", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("line 1"))
        XCTAssertTrue(content.contains("line 2"))
    }

    func testWriteAndReadMarkdown() throws {
        let file = tmpDir.appendingPathComponent("note.md")
        let fm = VTMDFileManager.shared
        let expected = "# Hello\n\nSome **bold** text."
        try fm.writeMarkdown(expected, to: file)
        let result = fm.readMarkdown(from: file)
        XCTAssertEqual(result, expected)
    }

    func testReadMarkdownReturnsEmptyForMissingFile() {
        let file = tmpDir.appendingPathComponent("nonexistent.md")
        let result = VTMDFileManager.shared.readMarkdown(from: file)
        XCTAssertEqual(result, "")
    }

    func testModelSizeLocalPath() {
        let dir = URL(fileURLWithPath: "/tmp/models")
        let path = ModelSize.base.localPath(in: dir)
        XCTAssertEqual(path.lastPathComponent, "ggml-base.bin")
    }

    func testModelSizeHuggingFaceURL() {
        let url = ModelSize.tiny.huggingFaceURL
        XCTAssertTrue(url.absoluteString.contains("ggml-tiny.bin"))
        XCTAssertTrue(url.absoluteString.contains("huggingface.co"))
    }
}
