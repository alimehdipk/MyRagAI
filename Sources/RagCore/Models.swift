import Foundation

public struct Source: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var path: String
    public var isFolder: Bool
    public var addedAt = Date()
    public var lastIndexedAt: Date?
    public var bookmark: Data?
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(path: String, isFolder: Bool, bookmark: Data? = nil) {
        self.path = path; self.isFolder = isFolder; self.bookmark = bookmark
    }
}

public struct TextChunk: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var text: String
    public var page: Int?
    public init(text: String, page: Int? = nil) { self.text = text; self.page = page }
}

public struct IndexedDocument: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var sourceID: UUID
    public var path: String
    public var modifiedAt: Date
    public var chunks: [TextChunk]
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(sourceID: UUID, path: String, modifiedAt: Date, chunks: [TextChunk]) {
        self.sourceID = sourceID; self.path = path; self.modifiedAt = modifiedAt; self.chunks = chunks
    }
}

public struct Citation: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var number: Int
    public var documentName: String
    public var path: String
    public var page: Int?
    public var excerpt: String
    public init(number: Int, documentName: String, path: String, page: Int?, excerpt: String) {
        self.number = number; self.documentName = documentName; self.path = path
        self.page = page; self.excerpt = excerpt
    }
}

public struct ChatMessage: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var role: String
    public var text: String
    public var citations: [Citation]
    public var createdAt = Date()
    public var providerLabel: String?
    public init(role: String, text: String, citations: [Citation] = [], providerLabel: String? = nil) {
        self.role = role; self.text = text; self.citations = citations; self.providerLabel = providerLabel
    }
}

public struct Conversation: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var title = "New conversation"
    public var messages: [ChatMessage] = []
    public var createdAt = Date()
    public init() {}
}

public enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case ollama = "Ollama"
    case lmStudio = "LM Studio"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case custom = "Custom compatible API"
    public var id: String { rawValue }
    public var defaultURL: String {
        switch self {
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .custom: return "http://localhost:8080/v1"
        }
    }
    public var needsKey: Bool { [.openAI, .openRouter, .anthropic].contains(self) }
}

public struct AIConnection: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var model: String
    public init(kind: ProviderKind = .ollama) {
        self.kind = kind; self.name = kind.rawValue; self.baseURL = kind.defaultURL; self.model = ""
    }
    public var isLocal: Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }
}

public struct WorkspaceState: Codable, Sendable {
    public var schemaVersion = 1
    public var sources: [Source] = []
    public var documents: [IndexedDocument] = []
    public var conversations: [Conversation] = []
    public var connections: [AIConnection] = [AIConnection()]
    public var activeConnectionID: UUID?
    public var excerptCount = 6
    public init() { activeConnectionID = connections.first?.id }
}

public enum RagError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
