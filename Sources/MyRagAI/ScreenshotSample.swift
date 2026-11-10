import Foundation
import RagCore

/// Public fixtures for documentation screenshots. No real provider response or private files.
enum ScreenshotSample {
    static func workspace() -> WorkspaceState {
        var state = WorkspaceState()
        let root = "/Sample Knowledge"
        var handbook = Source(path: root + "/Project Handbook", isFolder: true)
        var research = Source(path: root + "/Research Notes", isFolder: true)
        handbook.lastIndexedAt = Date()
        research.lastIndexedAt = Date()
        state.sources = [handbook, research]
        let launch = IndexedDocument(sourceID: handbook.id, path: handbook.path + "/Launch checklist.pdf", modifiedAt: Date(), chunks: [
            TextChunk(text: "Before release, complete the accessibility review, verify offline document search, and confirm the onboarding flow. The release owner records approval after the checklist is complete.", page: 3),
            TextChunk(text: "The first release includes document import, source-linked answers, and support for local AI servers. The team reviews user feedback every Friday.", page: 1)
        ])
        let guide = IndexedDocument(sourceID: handbook.id, path: handbook.path + "/Team guide.md", modifiedAt: Date(), chunks: [
            TextChunk(text: "Keep decisions in writing. Each decision should include context, alternatives, the owner, and the next review date."),
            TextChunk(text: "For release readiness, check the knowledge index after importing files, confirm provider settings, and review the citations in sample answers.")
        ])
        let researchDoc = IndexedDocument(sourceID: research.id, path: research.path + "/Research summary.md", modifiedAt: Date(), chunks: [
            TextChunk(text: "Participants wanted a faster way to locate answers across PDF reports and notes. Visible source excerpts helped them judge whether an answer was useful."),
            TextChunk(text: "Local indexing was preferred for private material. Participants also wanted the ability to switch between local and cloud model providers.")
        ])
        state.documents = [launch, guide, researchDoc]
        var local = AIConnection(kind: .ollama)
        local.name = "Local workspace"
        local.model = "your-local-chat-model"
        var cloud = AIConnection(kind: .openAI)
        cloud.name = "Cloud workspace"
        state.connections = [local, cloud]
        state.activeConnectionID = local.id
        var chat = Conversation()
        chat.title = "Getting ready for release"
        chat.messages = [
            ChatMessage(role: "user", text: "What should we check before our first release?"),
            ChatMessage(role: "assistant", text: "Start with the release checklist:\n\n• Complete the **accessibility review**.\n• Verify **offline document search**.\n• Confirm that the **onboarding flow** works end to end. [1]\n\nThen check the knowledge index, review provider settings, and verify the citations in sample answers. [2]\n\nThe release owner should record approval once the checklist is complete. [1]", citations: [
                Citation(number: 1, documentName: launch.name, path: launch.path, page: 3, excerpt: launch.chunks[0].text),
                Citation(number: 2, documentName: guide.name, path: guide.path, page: nil, excerpt: guide.chunks[1].text)
            ], providerLabel: "Documentation example · Sample content")
        ]
        state.conversations = [chat]
        return state
    }
}
