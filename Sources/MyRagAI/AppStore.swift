import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RagCore

enum WorkspacePage: String, CaseIterable {
    case chat = "Ask your knowledge", library = "Knowledge library", connections = "Connections"
    var icon: String {
        switch self { case .chat: return "bubble.left.and.text.bubble.right"; case .library: return "books.vertical"; case .connections: return "point.3.connected.trianglepath.dotted" }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var state = WorkspaceState()
    @Published var page = WorkspacePage.chat
    @Published var selectedConversationID: UUID?
    @Published var selectedSourceIDs: Set<UUID> = []
    @Published var isImporting = false
    @Published var importStatus = ""
    @Published var importWarnings: [String] = []
    @Published var isAnswering = false
    @Published var error: String?
    @Published var notice: String?
    @Published var draft = ""
    @Published var shownCitation: Citation?
    @Published var readOnly = false
    private var storage: WorkspaceStorage?
    private var index = LocalIndex(documents: [])
    private var responseTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var generationID: UUID?

    var activeConnection: AIConnection? { state.connections.first { $0.id == state.activeConnectionID } ?? state.connections.first }
    var currentConversation: Conversation? { state.conversations.first { $0.id == selectedConversationID } }
    var totalChunks: Int { state.documents.reduce(0) { $0 + $1.chunks.count } }
    var canAsk: Bool { !isAnswering && !isImporting && !readOnly && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.documents.isEmpty }

    init() {
        // A dedicated preview bundle uses only public sample data and never opens the saved workspace.
        if Bundle.main.object(forInfoDictionaryKey: "MyRagAIScreenshotMode") as? Bool == true {
            state = ScreenshotSample.workspace()
            index = LocalIndex(documents: state.documents)
            selectedConversationID = state.conversations.first?.id
            return
        }
        do {
            let storage = try WorkspaceStorage()
            self.storage = storage
            state = try storage.load()
            index = LocalIndex(documents: state.documents)
            selectedConversationID = state.conversations.first?.id
        } catch {
            readOnly = true
            self.error = "Your saved workspace could not be opened. It has been left untouched. \(error.localizedDescription)"
        }
    }
    func persist() {
        guard !readOnly else { return }
        do { try storage?.save(state) }
        catch { self.error = "Could not save the workspace: \(error.localizedDescription)" }
    }
    func newConversation() {
        guard !readOnly else { return }
        let conversation = Conversation()
        state.conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        draft = ""; shownCitation = nil; page = .chat
        persist()
    }
    func selectConversation(_ id: UUID) {
        selectedConversationID = id; page = .chat; shownCitation = nil
    }
    func deleteConversation(_ id: UUID) {
        if isAnswering || readOnly { return }
        state.conversations.removeAll { $0.id == id }
        if selectedConversationID == id { selectedConversationID = state.conversations.first?.id }
        shownCitation = nil
        persist()
    }
    func selectConnection(_ id: UUID) {
        guard !readOnly else { return }
        state.activeConnectionID = id; persist()
    }
    func saveConnection(_ connection: AIConnection, key: String) throws {
        guard !readOnly else { throw RagError.message("The workspace is read-only because loading failed.") }
        _ = try AIClient.endpoint(connection: connection, resource: "models")
        guard !connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RagError.message("Give this connection a name.") }
        try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), id: connection.id)
        if let index = state.connections.firstIndex(where: { $0.id == connection.id }) { state.connections[index] = connection }
        else { state.connections.append(connection) }
        state.activeConnectionID = connection.id
        persist()
    }
    func deleteConnection(_ id: UUID) throws {
        guard !readOnly else { throw RagError.message("The workspace is read-only because loading failed.") }
        try KeychainStore.save("", id: id)
        state.connections.removeAll { $0.id == id }
        if state.activeConnectionID == id { state.activeConnectionID = state.connections.first?.id }
        persist()
    }
    func chooseFiles(folder: Bool) {
        guard !isImporting, !readOnly else { return }
        let panel = NSOpenPanel()
        panel.title = folder ? "Add a knowledge folder" : "Add documents"
        panel.prompt = "Add to knowledge"
        panel.canChooseDirectories = folder; panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = true
        if !folder { panel.allowedContentTypes = DocumentImporter.extensions.compactMap { UTType(filenameExtension: $0) } }
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        guard !isImporting, !readOnly else { return }
        var sources: [Source] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !state.sources.contains(where: { $0.path == path }), !sources.contains(where: { $0.path == path }) else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            sources.append(Source(path: path, isFolder: values?.isDirectory == true, bookmark: bookmark))
        }
        guard !sources.isEmpty else { notice = "These sources are already in your library. Use Rescan to refresh them."; return }
        runImport(sources)
    }
    func rescan(_ sources: [Source]) {
        guard !sources.isEmpty, !isImporting, !readOnly else { return }
        runImport(sources)
    }
    private func runImport(_ sources: [Source]) {
        isImporting = true; importWarnings = []; page = .library
        importTask = Task {
            for source in sources {
                if Task.isCancelled { break }
                importStatus = "Indexing \(source.name)…"
                do {
                    let worker = Task.detached(priority: .userInitiated) { try DocumentImporter.index(source: source) }
                    let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                    state.documents.removeAll { $0.sourceID == source.id }
                    state.documents.append(contentsOf: result.documents)
                    var updated = source; updated.lastIndexedAt = Date()
                    if let i = state.sources.firstIndex(where: { $0.id == source.id }) { state.sources[i] = updated }
                    else { state.sources.append(updated) }
                    importWarnings.append(contentsOf: result.warnings)
                } catch is CancellationError { break }
                catch { importWarnings.append(error.localizedDescription) }
            }
            let documents = state.documents
            index = await Task.detached(priority: .userInitiated) { LocalIndex(documents: documents) }.value
            isImporting = false
            importStatus = "\(state.documents.count) documents ready to search"
            persist()
        }
    }
    func cancelImport() { importTask?.cancel() }
    func removeSource(_ source: Source) {
        guard !isImporting, !readOnly else { return }
        state.sources.removeAll { $0.id == source.id }
        state.documents.removeAll { $0.sourceID == source.id }
        selectedSourceIDs.remove(source.id)
        index = LocalIndex(documents: state.documents)
        persist()
    }
    func search(_ query: String) async -> [SearchHit] {
        let snapshot = index
        return await Task.detached(priority: .userInitiated) { snapshot.search(query, limit: 30) }.value
    }
    func ask(_ suggestion: String? = nil) {
        if let suggestion { draft = suggestion }
        guard canAsk else { return }
        guard let connection = activeConnection, !connection.model.isEmpty else {
            page = .connections; notice = "Choose your AI model and save a connection to start chatting."; return
        }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentConversation == nil { newConversation() }
        guard let conversationID = selectedConversationID, let position = state.conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let history = state.conversations[position].messages
        if history.isEmpty { state.conversations[position].title = String(question.prefix(55)) }
        state.conversations[position].messages.append(ChatMessage(role: "user", text: question))
        draft = ""; error = nil; shownCitation = nil; isAnswering = true
        persist()
        let requestID = UUID(); generationID = requestID
        let snapshot = index
        let documents = state.documents
        let sourceIDs = selectedSourceIDs.isEmpty ? nil : selectedSourceIDs
        let count = state.excerptCount
        responseTask = Task {
            defer { if generationID == requestID { isAnswering = false; generationID = nil } }
            do {
                let hits = await Task.detached(priority: .userInitiated) {
                    var hits = snapshot.search(question, limit: count, sourceIDs: sourceIDs)
                    // Resolve short follow-ups using the last user question if the new wording has no matches.
                    if hits.isEmpty, question.count < 100, let previous = history.last(where: { $0.role == "user" }) {
                        hits = snapshot.search(question + " " + previous.text, limit: count, sourceIDs: sourceIDs)
                    }
                    return hits
                }.value
                try Task.checkCancellation()
                var citations = hits.enumerated().map { $0.element.citation(number: $0.offset + 1) }
                let overview = ["summar", "overview", "main topics", "key points"].contains { question.lowercased().contains($0) }
                if citations.isEmpty && overview {
                    // Sample across documents; never pretend a sampled overview is a full-document summary.
                    let scoped = documents.filter { sourceIDs == nil || sourceIDs!.contains($0.sourceID) }
                    for document in scoped.prefix(count) {
                        if let chunk = document.chunks.first {
                            citations.append(Citation(number: citations.count + 1, documentName: document.name, path: document.path, page: chunk.page, excerpt: chunk.text))
                        }
                    }
                }
                if citations.isEmpty {
                    append(ChatMessage(role: "assistant", text: "I couldn’t find a matching passage in the selected sources. Try including a specific name, topic, or phrase from your documents, or choose a different source scope."), to: conversationID)
                    return
                }
                let key = try KeychainStore.read(id: connection.id)
                let answer = try await AIClient().complete(connection: connection, key: key, question: question, citations: citations, history: history)
                try Task.checkCancellation()
                guard generationID == requestID else { return }
                append(ChatMessage(role: "assistant", text: answer, citations: citations, providerLabel: "\(connection.name) · \(connection.model)"), to: conversationID)
            } catch is CancellationError { }
            catch {
                if !Task.isCancelled { self.error = error.localizedDescription; draft = question }
            }
        }
    }
    func stopAnswer() { responseTask?.cancel(); generationID = nil; isAnswering = false }
    private func append(_ message: ChatMessage, to conversationID: UUID) {
        if let index = state.conversations.firstIndex(where: { $0.id == conversationID }) {
            state.conversations[index].messages.append(message); persist()
        }
    }
    func openCitation(_ citation: Citation) {
        let url = URL(fileURLWithPath: citation.path)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
        else { error = "The original file has moved or is unavailable. The saved excerpt is still shown here." }
    }
}
