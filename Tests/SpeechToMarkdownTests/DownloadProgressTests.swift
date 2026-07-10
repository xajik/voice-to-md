import XCTest
@testable import SpeechToMarkdown

final class DownloadProgressTests: XCTestCase {

    // MARK: - fraction

    func testFractionZeroWhenTotalIsZero() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 0, bytesTotal: 0, isComplete: false, error: nil)
        XCTAssertEqual(progress.fraction, 0.0)
    }

    func testFractionZeroAtStart() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 0, bytesTotal: 1000, isComplete: false, error: nil)
        XCTAssertEqual(progress.fraction, 0.0)
    }

    func testFractionOneWhenComplete() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 1000, bytesTotal: 1000, isComplete: true, error: nil)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.001)
    }

    func testFractionHalfway() {
        let progress = DownloadProgress(modelSize: .tiny, bytesDownloaded: 500, bytesTotal: 1000, isComplete: false, error: nil)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
    }

    func testFractionNeverExceedsOne() {
        let progress = DownloadProgress(modelSize: .large, bytesDownloaded: 2000, bytesTotal: 1000, isComplete: true, error: nil)
        XCTAssertGreaterThanOrEqual(progress.fraction, 0)
    }

    // MARK: - percentage

    func testPercentageZeroAtStart() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 0, bytesTotal: 1000, isComplete: false, error: nil)
        XCTAssertEqual(progress.percentage, 0)
    }

    func testPercentage100WhenComplete() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 1000, bytesTotal: 1000, isComplete: true, error: nil)
        XCTAssertEqual(progress.percentage, 100)
    }

    func testPercentage50Halfway() {
        let progress = DownloadProgress(modelSize: .small, bytesDownloaded: 500, bytesTotal: 1000, isComplete: false, error: nil)
        XCTAssertEqual(progress.percentage, 50)
    }

    func testPercentageIsIntegerTruncation() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 1, bytesTotal: 3, isComplete: false, error: nil)
        XCTAssertEqual(progress.percentage, 33)
    }

    // MARK: - isComplete / error

    func testIsCompleteFlag() {
        let done = DownloadProgress(modelSize: .tiny, bytesDownloaded: 100, bytesTotal: 100, isComplete: true, error: nil)
        XCTAssertTrue(done.isComplete)

        let inProgress = DownloadProgress(modelSize: .tiny, bytesDownloaded: 50, bytesTotal: 100, isComplete: false, error: nil)
        XCTAssertFalse(inProgress.isComplete)
    }

    func testErrorIsNilOnSuccess() {
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 100, bytesTotal: 100, isComplete: true, error: nil)
        XCTAssertNil(progress.error)
    }

    func testErrorIsSetOnFailure() {
        let err = NSError(domain: "test", code: 1)
        let progress = DownloadProgress(modelSize: .base, bytesDownloaded: 0, bytesTotal: 0, isComplete: false, error: err)
        XCTAssertNotNil(progress.error)
    }

    // MARK: - modelSize

    func testModelSizeIsPreserved() {
        let progress = DownloadProgress(modelSize: .medium, bytesDownloaded: 0, bytesTotal: 1000, isComplete: false, error: nil)
        XCTAssertEqual(progress.modelSize, .medium)
    }
}
