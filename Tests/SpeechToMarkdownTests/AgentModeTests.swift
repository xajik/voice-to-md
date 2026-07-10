import XCTest
@testable import SpeechToMarkdown

final class AgentModeTests: XCTestCase {

    func testAllCasesOrder() {
        XCTAssertEqual(AgentMode.allCases, [.format, .edit, .append])
    }

    func testIconNames() {
        XCTAssertEqual(AgentMode.format.iconName, "doc.text")
        XCTAssertEqual(AgentMode.edit.iconName, "pencil")
        XCTAssertEqual(AgentMode.append.iconName, "plus")
    }

    func testDisplayNames() {
        XCTAssertEqual(AgentMode.format.displayName, "Format")
        XCTAssertEqual(AgentMode.edit.displayName, "Edit")
        XCTAssertEqual(AgentMode.append.displayName, "Append")
    }
}
