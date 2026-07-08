import XCTest
@testable import VoiceToMarkdown

final class ModelSizeTests: XCTestCase {

    // MARK: - filename

    func testFilenameFormat() {
        XCTAssertEqual(ModelSize.tiny.filename, "ggml-tiny.bin")
        XCTAssertEqual(ModelSize.base.filename, "ggml-base.bin")
        XCTAssertEqual(ModelSize.small.filename, "ggml-small.bin")
        XCTAssertEqual(ModelSize.medium.filename, "ggml-medium.bin")
        XCTAssertEqual(ModelSize.large.filename, "ggml-large-v3.bin")
    }

    func testAllFilenamesEndWithDotBin() {
        for size in ModelSize.allCases {
            XCTAssertTrue(size.filename.hasSuffix(".bin"), "\(size) filename should end with .bin")
        }
    }

    func testAllFilenamesStartWithGgml() {
        for size in ModelSize.allCases {
            XCTAssertTrue(size.filename.hasPrefix("ggml-"), "\(size) filename should start with ggml-")
        }
    }

    // MARK: - approximateSize

    func testApproximateSizeNonEmpty() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.approximateSize.isEmpty)
        }
    }

    func testApproximateSizeContainsMBOrGB() {
        for size in ModelSize.allCases {
            let hasMB = size.approximateSize.contains("MB")
            let hasGB = size.approximateSize.contains("GB")
            XCTAssertTrue(hasMB || hasGB, "\(size) approximateSize should contain MB or GB")
        }
    }

    // MARK: - huggingFaceURL

    func testHuggingFaceURLIsHTTPS() {
        for size in ModelSize.allCases {
            XCTAssertEqual(size.huggingFaceURL.scheme, "https")
        }
    }

    func testHuggingFaceURLContainsFilename() {
        for size in ModelSize.allCases {
            XCTAssertTrue(
                size.huggingFaceURL.absoluteString.contains(size.filename),
                "\(size) URL should contain its filename"
            )
        }
    }

    func testHuggingFaceURLContainsHuggingFaceDomain() {
        for size in ModelSize.allCases {
            XCTAssertTrue(size.huggingFaceURL.absoluteString.contains("huggingface.co"))
        }
    }

    func testTinyURL() {
        XCTAssertTrue(ModelSize.tiny.huggingFaceURL.absoluteString.contains("ggml-tiny.bin"))
    }

    func testLargeURL() {
        XCTAssertTrue(ModelSize.large.huggingFaceURL.absoluteString.contains("ggml-large-v3.bin"))
    }

    // MARK: - localPath

    func testLocalPathIsInsideGivenDirectory() {
        let dir = URL(fileURLWithPath: "/tmp/models")
        for size in ModelSize.allCases {
            let path = size.localPath(in: dir)
            XCTAssertTrue(path.path.hasPrefix(dir.path))
        }
    }

    func testLocalPathFilenameMatchesModelFilename() {
        let dir = URL(fileURLWithPath: "/tmp/models")
        for size in ModelSize.allCases {
            XCTAssertEqual(size.localPath(in: dir).lastPathComponent, size.filename)
        }
    }

    // MARK: - id (Identifiable)

    func testIdMatchesRawValue() {
        for size in ModelSize.allCases {
            XCTAssertEqual(size.id, size.rawValue)
        }
    }

    func testAllIdsAreUnique() {
        let ids = ModelSize.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    // MARK: - CaseIterable

    func testAllCasesCount() {
        XCTAssertEqual(ModelSize.allCases.count, 5)
    }
}
