import Foundation

// Minimal assertions keep the checks runnable on Macs with Command Line Tools only.
// Every failed assertion is recorded and the runner exits nonzero.
private var failures: [String] = []

func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: String = #filePath, line: UInt = #line) {
    do { if try lhs() != rhs() { failures.append("\(file):\(line): values are not equal") } }
    catch { failures.append("\(file):\(line): \(error)") }
}
func XCTAssertTrue(_ condition: @autoclosure () throws -> Bool, file: String = #filePath, line: UInt = #line) {
    do { if try !condition() { failures.append("\(file):\(line): expected true") } }
    catch { failures.append("\(file):\(line): \(error)") }
}
func XCTAssertFalse(_ condition: @autoclosure () throws -> Bool, file: String = #filePath, line: UInt = #line) {
    do { if try condition() { failures.append("\(file):\(line): expected false") } }
    catch { failures.append("\(file):\(line): \(error)") }
}
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: String = #filePath, line: UInt = #line) {
    do { if try value() == nil { failures.append("\(file):\(line): expected a value") } }
    catch { failures.append("\(file):\(line): \(error)") }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: String = #filePath, line: UInt = #line) {
    do { _ = try expression(); failures.append("\(file):\(line): expected an error") } catch { }
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "CoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a value"]) }
    return value
}

@main
struct Runner {
    static func main() {
        let checks = CoreChecks()
        let cases: [(String, () throws -> Void)] = [
            ("Unicode chunking and overlap", checks.testChunkingPreservesUnicodeAndOverlap),
            ("Bounded long-token excerpts", checks.testLongUnbrokenTextHasBoundedExcerpts),
            ("Ranking and source filtering", checks.testSearchRanksRelevantPassagesAndRespectsScope),
            ("Citations and grounding prompt", checks.testCitationAndPromptContainEvidenceAndPage),
            ("Endpoint validation", checks.testEndpointValidation),
            ("Provider request contracts", checks.testProviderRequestFormatsAndValidation),
            ("Provider response decoding", checks.testResponseDecoding),
            ("Persistence and corrupt-file protection", checks.testPersistenceRoundTripAndCorruptFileProtection),
            ("Folder import and rescan", checks.testFolderImportRescanAndUnsupportedFiles),
            ("PDF extraction and page numbers", checks.testPDFExtractionPreservesPageNumbers)
        ]
        for (name, check) in cases {
            let before = failures.count
            do { try check() } catch { failures.append("\(name): \(error)") }
            print("\(failures.count == before ? "PASS" : "FAIL")  \(name)")
        }
        for failure in failures { print(failure) }
        print("\(cases.count) checks completed; \(failures.count) failures.")
        if !failures.isEmpty { exit(1) }
    }
}
