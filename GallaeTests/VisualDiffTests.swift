import XCTest
@testable import Gallae

final class VisualDiffTests: XCTestCase {
    private var example: Data {
        Data("""
        {"kind":"graph","title":"Change overview","lenses":["architecture","data-flow"],
         "provenance":{"repo":{"owner":"team","name":"project"},
         "base":{"sha":"0123456789abcdef"},"head":{"sha":"abcdef0123456789"}}}
        """.utf8)
    }

    func testImportRetainsSourceAndAvailableLenses() throws {
        let graph = try VisualDiffDocument(data: example)
        XCTAssertEqual(graph.title, "Change overview")
        XCTAssertEqual(graph.lenses, ["architecture", "data-flow"])
        XCTAssertEqual(graph.sourceDescription, "team/project · 01234567 → abcdef01")
        XCTAssertEqual(Data(graph.json.utf8), example)
    }

    func testRejectsManifestInvalidJSONAndUnsupportedEncoding() {
        for data in [Data("{\"kind\":\"render-manifest\"}".utf8), Data("not JSON".utf8), Data([0xff, 0xfe])] {
            XCTAssertThrowsError(try VisualDiffDocument(data: data))
        }
    }

    func testOversizedImportIsRejectedBeforeParsing() {
        XCTAssertThrowsError(try VisualDiffDocument(data: Data(repeating: 32, count: VisualDiffDocument.maximumBytes + 1))) { error in
            XCTAssertEqual(error as? VisualDiffDocument.ImportError, .tooLarge)
        }
    }

    func testUnknownLensesAreSkippedButKnownViewIsRequired() throws {
        let json = String(decoding: example, as: UTF8.self)
        let future = json.replacingOccurrences(of: "\"architecture\",\"data-flow\"", with: "\"future\",\"architecture\"")
        XCTAssertEqual(try VisualDiffDocument(data: Data(future.utf8)).lenses, ["architecture"])
        let unsupported = json.replacingOccurrences(of: "\"architecture\",\"data-flow\"", with: "\"future\"")
        XCTAssertThrowsError(try VisualDiffDocument(data: Data(unsupported.utf8)))
    }
}
