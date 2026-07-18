import XCTest
@testable import SpeechToMarkdown

final class SpeechTextResolutionTests: XCTestCase {
    // MARK: - Selection precedence

    func testSelectionWinsOverDocument() {
        let text = SpeechSynthesisService.textToSpeak(selection: "just this", document: "# Full document")
        XCTAssertEqual(text, "just this")
    }

    func testNilSelectionFallsBackToDocument() {
        let text = SpeechSynthesisService.textToSpeak(selection: nil, document: "# Full document")
        XCTAssertEqual(text, "# Full document")
    }

    // MARK: - Trimming

    func testResultIsTrimmed() {
        let text = SpeechSynthesisService.textToSpeak(selection: "  hello world \n", document: "doc")
        XCTAssertEqual(text, "hello world")
    }

    // MARK: - Empty inputs

    func testEmptyDocumentReturnsNil() {
        XCTAssertNil(SpeechSynthesisService.textToSpeak(selection: nil, document: ""))
    }

    func testWhitespaceOnlyDocumentReturnsNil() {
        XCTAssertNil(SpeechSynthesisService.textToSpeak(selection: nil, document: "  \n\t "))
    }

    func testWhitespaceOnlySelectionReturnsNil() {
        // A blank selection is not readable; it does not fall back to the document.
        XCTAssertNil(SpeechSynthesisService.textToSpeak(selection: "   ", document: "# Full document"))
    }
}
