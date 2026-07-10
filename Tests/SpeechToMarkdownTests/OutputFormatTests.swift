import XCTest
@testable import SpeechToMarkdown

final class OutputFormatTests: XCTestCase {

    func testAllCasesOrder() {
        XCTAssertEqual(OutputFormat.allCases, [.txt, .md, .html])
    }

    func testDisplayNames() {
        XCTAssertEqual(OutputFormat.txt.displayName, "Plain Text")
        XCTAssertEqual(OutputFormat.md.displayName, "Markdown")
        XCTAssertEqual(OutputFormat.html.displayName, "HTML")
    }

    func testFileExtensionsMatchRawValues() {
        for format in OutputFormat.allCases {
            XCTAssertEqual(format.fileExtension, format.rawValue)
        }
    }

    func testPromptExpectationsAreDistinctAndContainExample() {
        let expectations = OutputFormat.allCases.map(\.promptExpectations)
        XCTAssertEqual(Set(expectations).count, expectations.count)
        for expectation in expectations {
            XCTAssertFalse(expectation.isEmpty)
            XCTAssertTrue(expectation.contains("Example"))
        }
    }
}
