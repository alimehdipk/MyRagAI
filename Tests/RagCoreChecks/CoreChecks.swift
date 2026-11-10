import PDFKit
import AppKit
import CoreText
import RagCore

final class CoreChecks {
    func testChunkingPreservesUnicodeAndOverlap() {
        let text = (0..<600).map { "word\($0)" }.joined(separator: " ") + " اردو café 🎵"
        let chunks = Chunker.split(text, page: 7, size: 260, overlap: 45)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks[1].text.hasPrefix("word215 "))
        XCTAssertTrue(chunks.last!.text.hasSuffix("اردو café 🎵"))
        XCTAssertEqual(chunks[0].page, 7)
        XCTAssertTrue(Chunker.split(" \n ").isEmpty)
        XCTAssertTrue(Chunker.split("hello", size: 2, overlap: 2).isEmpty)
    }

    func testLongUnbrokenTextHasBoundedExcerpts() {
        let chunks = Chunker.split(String(repeating: "x", count: 15000))
        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 6000 })
    }

    func testSearchRanksRelevantPassagesAndRespectsScope() {
        let a = UUID(), b = UUID()
        let docs = [
            doc("release.md", "The deployment deadline is November 22. Release approval requires QA signoff.", source: a),
            doc("recipes.txt", "The cake contains flour, cocoa, and eggs.", source: b),
            doc("notes.txt", "Deployment engineers review configuration before deployment.", source: a)
        ]
        let index = LocalIndex(documents: docs)
        XCTAssertEqual(index.search("What is the deployment deadline?").first?.document.name, "release.md")
        XCTAssertTrue(index.search("cocoa", sourceIDs: [a]).isEmpty)
        XCTAssertEqual(index.search("cocoa", sourceIDs: [b]).count, 1)
        XCTAssertTrue(index.search("quantum astrophysics").isEmpty)
        XCTAssertTrue(index.search("the and is").isEmpty)
        XCTAssertEqual(index.search("deployment", limit: 1).count, 1)
        XCTAssertEqual(LocalIndex.tokenize("CAFÉ café"), ["cafe", "cafe"])
    }

    func testCitationAndPromptContainEvidenceAndPage() {
        let citation = Citation(number: 1, documentName: "manual.pdf", path: "/tmp/manual.pdf", page: 12, excerpt: "The red switch stops the motor.")
        let prompt = PromptBuilder.question("What stops it?", citations: [citation])
        XCTAssertTrue(prompt.contains("[1] manual.pdf, page 12"))
        XCTAssertTrue(prompt.contains(citation.excerpt))
        XCTAssertTrue(PromptBuilder.system.contains("untrusted"))
        XCTAssertTrue(PromptBuilder.system.contains("Do not invent"))
    }

    func testEndpointValidation() throws {
        var connection = AIConnection()
        connection.baseURL = "http://localhost:11434/v1/"
        XCTAssertEqual(try AIClient.endpoint(connection: connection, resource: "chat/completions").absoluteString, "http://localhost:11434/v1/chat/completions")
        connection.baseURL = "http://example.com/v1"
        XCTAssertThrowsError(try AIClient.endpoint(connection: connection, resource: "models"))
        connection.baseURL = "https://user:secret@example.com/v1"
        XCTAssertThrowsError(try AIClient.endpoint(connection: connection, resource: "models"))
        connection.baseURL = "https://example.com/v1?key=secret"
        XCTAssertThrowsError(try AIClient.endpoint(connection: connection, resource: "models"))
        connection.baseURL = "file:///etc/passwd"
        XCTAssertThrowsError(try AIClient.endpoint(connection: connection, resource: "models"))
        connection.baseURL = "https://example.com/custom/v1"
        XCTAssertEqual(try AIClient.endpoint(connection: connection, resource: "models").path, "/custom/v1/models")
    }

    func testProviderRequestFormatsAndValidation() throws {
        let client = AIClient()
        var connection = AIConnection(kind: .openAI)
        XCTAssertThrowsError(try client.request(connection: connection, key: "", system: "system", messages: []))
        connection.model = "test-model"
        XCTAssertThrowsError(try client.request(connection: connection, key: "", system: "system", messages: []))
        let request = try client.request(connection: connection, key: "test-key", system: "system", messages: [["role": "user", "content": "hi"]])
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertNotNil(body["max_completion_tokens"])
        XCTAssertEqual((body["messages"] as? [[String: String]])?.first?["role"], "system")
        connection = AIConnection(kind: .anthropic); connection.model = "test-claude"
        let claude = try client.request(connection: connection, key: "test-key", system: "system", messages: [["role": "user", "content": "hi"]])
        XCTAssertEqual(claude.url?.path, "/v1/messages")
        XCTAssertEqual(claude.value(forHTTPHeaderField: "x-api-key"), "test-key")
        let claudeBody = try XCTUnwrap(JSONSerialization.jsonObject(with: claude.httpBody!) as? [String: Any])
        XCTAssertEqual(claudeBody["system"] as? String, "system")
        XCTAssertNotNil(claudeBody["max_tokens"])
    }

    func testResponseDecoding() throws {
        XCTAssertEqual(try AIClient.answer(from: Data(#"{"choices":[{"message":{"content":"Answer [1]"}}]}"#.utf8), anthropic: false), "Answer [1]")
        XCTAssertEqual(try AIClient.answer(from: Data(#"{"content":[{"type":"text","text":"First"},{"type":"text","text":"Second"}]}"#.utf8), anthropic: true), "First\nSecond")
        XCTAssertThrowsError(try AIClient.answer(from: Data(#"{"choices":[]}"#.utf8), anthropic: false))
    }

    func testPersistenceRoundTripAndCorruptFileProtection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try WorkspaceStorage(directory: directory)
        var state = WorkspaceState()
        let source = Source(path: "/tmp/manual.pdf", isFolder: false)
        state.sources = [source]
        state.documents = [doc("manual.pdf", "Important knowledge", source: source.id)]
        var conversation = Conversation()
        conversation.messages = [ChatMessage(role: "assistant", text: "Evidence [1]", citations: [Citation(number: 1, documentName: "manual.pdf", path: "/tmp/manual.pdf", page: 2, excerpt: "Evidence")])]
        state.conversations = [conversation]
        try storage.save(state)
        let restored = try storage.load()
        XCTAssertEqual(restored.sources, state.sources)
        XCTAssertEqual(restored.documents, state.documents)
        XCTAssertEqual(restored.conversations[0].messages[0].citations[0].page, 2)
        XCTAssertEqual(restored.activeConnectionID, state.activeConnectionID)
        let serialized = try String(contentsOf: storage.url)
        XCTAssertFalse(serialized.contains("apiKey"))
        try Data("bad json".utf8).write(to: storage.url)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try String(contentsOf: storage.url), "bad json")
    }

    func testFolderImportRescanAndUnsupportedFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "The moon mission launches in December.".write(to: directory.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2]).write(to: directory.appendingPathComponent("binary.txt"))
        try "hidden".write(to: directory.appendingPathComponent(".hidden.txt"), atomically: true, encoding: .utf8)
        try "ignore".write(to: directory.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        let source = Source(path: directory.path, isFolder: true)
        let result = try DocumentImporter.index(source: source)
        XCTAssertEqual(result.documents.count, 1)
        XCTAssertEqual(result.documents.first?.name, "notes.md")
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.scannedCount, 2)
        try "The mission moved to January.".write(to: directory.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try DocumentImporter.index(source: source).documents[0].chunks[0].text.contains("January"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("notes.md"))
        XCTAssertEqual(try DocumentImporter.index(source: source).documents.count, 0)
    }

    func testPDFExtractionPreservesPageNumbers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("sample.pdf")
        let text = NSAttributedString(string: "The project codename is Emerald.", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: 30, y: 200)
        CTLineDraw(line, context)
        context.endPDFPage(); context.closePDF()
        try (data as Data).write(to: file)
        let result = try DocumentImporter.index(source: Source(path: file.path, isFolder: false))
        XCTAssertEqual(result.documents.count, 1)
        XCTAssertEqual(result.documents.first?.chunks.first?.page, 1)
        XCTAssertTrue(result.documents.first?.chunks.first?.text.contains("Emerald") == true)
    }

    private func doc(_ name: String, _ text: String, source: UUID) -> IndexedDocument {
        IndexedDocument(sourceID: source, path: "/tmp/\(name)", modifiedAt: Date(), chunks: Chunker.split(text))
    }
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("myrag-tests-\(UUID().uuidString)") }
}
