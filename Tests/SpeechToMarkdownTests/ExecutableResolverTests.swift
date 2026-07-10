import XCTest
@testable import SpeechToMarkdown

final class ExecutableResolverTests: XCTestCase {
    func testResolvesBinaryFromPATH() {
        let url = ExecutableResolver.resolve("ls")
        XCTAssertNotNil(url)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url?.path ?? ""))
    }

    func testReturnsNilForUnknownBinary() {
        XCTAssertNil(ExecutableResolver.resolve("stmd-definitely-not-a-real-binary"))
    }

    func testEarlierNameWins() {
        let url = ExecutableResolver.resolve("ls", "cat")
        XCTAssertEqual(url?.lastPathComponent, "ls")
    }

    func testFallsBackAcrossNames() {
        let url = ExecutableResolver.resolve("stmd-definitely-not-a-real-binary", "ls")
        XCTAssertEqual(url?.lastPathComponent, "ls")
    }

    func testHomebrewDirectoriesAreProbed() {
        XCTAssertEqual(ExecutableResolver.fallbackDirectories, ["/opt/homebrew/bin", "/usr/local/bin"])
    }
}
