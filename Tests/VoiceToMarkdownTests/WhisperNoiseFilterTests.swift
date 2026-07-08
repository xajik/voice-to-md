import XCTest
@testable import VoiceToMarkdown

final class WhisperNoiseFilterTests: XCTestCase {

    func testParenAnnotationIsNoise() {
        XCTAssertTrue(WhisperService.isNoiseOnly("(wind blowing)"))
        XCTAssertTrue(WhisperService.isNoiseOnly("(soft music)"))
        XCTAssertTrue(WhisperService.isNoiseOnly("(mouse clicking) (mouse clicking)"))
    }

    func testBracketAnnotationIsNoise() {
        XCTAssertTrue(WhisperService.isNoiseOnly("[silence]"))
        XCTAssertTrue(WhisperService.isNoiseOnly("[BLANK_AUDIO]"))
        XCTAssertTrue(WhisperService.isNoiseOnly("[SIGHS] [BELL RINGING]"))
    }

    func testMixedAnnotationsAreNoise() {
        XCTAssertTrue(WhisperService.isNoiseOnly("(sniffing) [sobbing]"))
        XCTAssertTrue(WhisperService.isNoiseOnly("  (laughs)  "))
    }

    func testSpeechIsNotNoise() {
        XCTAssertFalse(WhisperService.isNoiseOnly("Hello world"))
        XCTAssertFalse(WhisperService.isNoiseOnly("The quick brown fox"))
    }

    func testSpeechWithEmbeddedAnnotationIsNotNoise() {
        XCTAssertFalse(WhisperService.isNoiseOnly("(soft music) welcome to the show"))
        XCTAssertFalse(WhisperService.isNoiseOnly("so the plan is [pause] to ship it"))
    }

    func testEmptyStringIsNoise() {
        XCTAssertTrue(WhisperService.isNoiseOnly(""))
        XCTAssertTrue(WhisperService.isNoiseOnly("   "))
    }
}
