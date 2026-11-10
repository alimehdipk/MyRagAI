import Foundation

public struct AIClient: Sendable {
    public init() {}

    public static func endpoint(connection: AIConnection, resource: String) throws -> URL {
        guard var parts = URLComponents(string: connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw RagError.message("Enter a valid API base URL, such as http://localhost:11434/v1. Do not include credentials or a query string.")
        }
        if scheme == "http" && !connection.isLocal {
            throw RagError.message("Remote connections require HTTPS. HTTP is supported only for localhost.")
        }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + ([parts.path, resource].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = parts.url else { throw RagError.message("The API URL is not valid.") }
        return url
    }

    public func request(connection: AIConnection, key: String, system: String, messages: [[String: String]], maxTokens: Int = 2048) throws -> URLRequest {
        guard !connection.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RagError.message("Choose a model in Connections first.")
        }
        if connection.kind.needsKey && key.isEmpty { throw RagError.message("Add an API key for \(connection.name) in Connections.") }
        let anthropic = connection.kind == .anthropic
        var request = URLRequest(url: try Self.endpoint(connection: connection, resource: anthropic ? "messages" : "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": connection.model, "stream": false]
        if anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = system
            body["messages"] = messages
            body["max_tokens"] = maxTokens
        } else {
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body["messages"] = [["role": "system", "content": system]] + messages
            body[connection.kind == .openAI ? "max_completion_tokens" : "max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func complete(connection: AIConnection, key: String, question: String, citations: [Citation], history: [ChatMessage]) async throws -> String {
        // Bound history independently of library size. Do not resend old excerpts to a new provider.
        var messages = history.suffix(8).map { ["role": $0.role, "content": String($0.text.prefix(4000))] }
        while messages.first?["role"] == "assistant" { messages.removeFirst() }
        messages.append(["role": "user", "content": PromptBuilder.question(question, citations: citations)])
        let req = try request(connection: connection, key: key, system: PromptBuilder.system, messages: messages)
        return try Self.answer(from: await send(req), anthropic: connection.kind == .anthropic)
    }

    public func test(connection: AIConnection, key: String) async throws -> String {
        let req = try request(connection: connection, key: key, system: "Reply briefly.", messages: [["role": "user", "content": "Reply with OK."]], maxTokens: 128)
        _ = try Self.answer(from: await send(req), anthropic: connection.kind == .anthropic)
        return "Connected to \(connection.model)."
    }

    public func models(connection: AIConnection, key: String) async throws -> [String] {
        var request = URLRequest(url: try Self.endpoint(connection: connection, resource: "models"))
        request.timeoutInterval = 20
        if connection.kind == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let data = try await send(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["data"] as? [[String: Any]] else { throw RagError.message("This server did not return a model list. Enter the model ID manually.") }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    private func send(_ request: URLRequest) async throws -> Data {
        // Disallow redirects so API keys and document excerpts never follow an endpoint to another host.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RagError.message("The server returned an invalid response.") }
        guard (200..<300).contains(response.statusCode) else {
            // Do not surface response bodies: providers may echo credentials or full prompts.
            let message: String
            switch response.statusCode {
            case 401, 403: message = "Authentication failed. Check the API key and its permissions."
            case 404: message = "Endpoint or model not found. Check the base URL and model ID."
            case 429: message = "The provider's rate or usage limit was reached. Try again later."
            case 300..<400: message = "The server redirected the request. Use the final API base URL directly."
            default: message = "The provider could not complete the request. Check the model, API settings, and server logs."
            }
            throw RagError.message("\(message) (HTTP \(response.statusCode))")
        }
        return data
    }

    public static func answer(from data: Data, anthropic: Bool) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RagError.message("The provider returned an unreadable response.")
        }
        let text: String?
        if anthropic {
            text = (root["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            let choice = (root["choices"] as? [[String: Any]])?.first
            let message = choice?["message"] as? [String: Any]
            text = message?["content"] as? String
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RagError.message("The model returned no answer text. Try a different chat model or question.")
        }
        return text
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
