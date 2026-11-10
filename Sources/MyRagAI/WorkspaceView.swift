import SwiftUI
import RagCore

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 240)
            Rectangle().fill(Color.line).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Color.line).frame(height: 1)
                if let error = store.error { banner(error, isError: true) }
                if let notice = store.notice { banner(notice, isError: false) }
                if store.readOnly {
                    Text("Workspace recovery required. Restart after restoring a valid workspace.json in Application Support/MyRagAI.")
                        .font(.caption).foregroundStyle(.orange).padding()
                }
                Group {
                    switch store.page {
                    case .chat: ChatView()
                    case .library: LibraryView()
                    case .connections: ConnectionsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.canvas).tint(.mint)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 33)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MyRagAI").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("YOUR PERSONAL KNOWLEDGE").font(.system(size: 7, weight: .medium)).tracking(1.2).foregroundStyle(Color.muted)
                }
            }.padding(.top, 43).padding(.bottom, 29).padding(.horizontal, 21)
            Button { store.newConversation() } label: {
                HStack { Image(systemName: "plus"); Text("New conversation"); Spacer(); Text("⌘N").font(.caption).opacity(0.55) }
            }.buttonStyle(QuietButton()).padding(.horizontal, 15).padding(.bottom, 24).disabled(store.readOnly)
            VStack(spacing: 5) {
                ForEach(WorkspacePage.allCases, id: \.self) { page in
                    Button { store.page = page } label: {
                        HStack(spacing: 11) {
                            Image(systemName: page.icon).frame(width: 19)
                            Text(page.rawValue).font(.system(size: 12, weight: .medium))
                            Spacer()
                            if page == .library {
                                Text("\(store.state.sources.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.muted)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 12)
                            .foregroundStyle(store.page == page ? Color.mint : Color.muted)
                            .background(store.page == page ? Color.mint.opacity(0.08) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12)
            HStack {
                Text("RECENT CONVERSATIONS").font(.system(size: 9, weight: .medium)).tracking(1.3)
                Spacer()
            }.foregroundStyle(Color.muted).padding(.horizontal, 23).padding(.top, 32).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.state.conversations.isEmpty {
                        Text("Your conversations will appear here.").font(.system(size: 11)).foregroundStyle(Color.muted).padding(12)
                    }
                    ForEach(store.state.conversations) { conversation in
                        Button { store.selectConversation(conversation.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "bubble.left").font(.system(size: 11))
                                Text(conversation.title).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 12).padding(.vertical, 10)
                                .foregroundStyle(store.selectedConversationID == conversation.id && store.page == .chat ? Color.primary : Color.muted)
                                .background(store.selectedConversationID == conversation.id && store.page == .chat ? Color.panel : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).contextMenu {
                            Button("Delete conversation", role: .destructive) { store.deleteConversation(conversation.id) }.disabled(store.isAnswering)
                        }
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 10)
            HStack(spacing: 4) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button { appearance = mode } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 31)
                            .foregroundStyle(appearance == mode ? Color.canvas : Color.muted)
                            .background(appearance == mode ? Color.mint : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .help(mode == .system ? "Follow system appearance" : "Use \(mode.title.lowercased()) appearance")
                        .accessibilityLabel("\(mode.title) appearance")
                        .accessibilityValue(appearance == mode ? "Selected" : "Not selected")
                }
            }.padding(4).background(Color.panel)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.line))
                .accessibilityElement(children: .contain).accessibilityLabel("Appearance")
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "internaldrive").foregroundStyle(Color.mint)
                    Text("Stored on this Mac").font(.system(size: 11, weight: .medium))
                }
                Text("\(store.state.documents.count) documents · \(store.totalChunks) excerpts")
                    .font(.system(size: 10)).foregroundStyle(Color.muted)
                Rectangle().fill(Color.line).frame(height: 1)
                Button { store.page = .connections } label: {
                    HStack {
                        Circle().fill(store.activeConnection?.model.isEmpty == false ? Color.mint : Color.orange).frame(width: 6, height: 6)
                        Text(store.activeConnection?.name ?? "Set up a connection").font(.system(size: 11))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                    }.foregroundStyle(Color.muted)
                }.buttonStyle(.plain)
            }.padding(16).background(Color.panel.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 11)).padding(15)
        }.background(Color.sidebar)
    }
    private var topBar: some View {
        HStack {
            Text("Workspace").foregroundStyle(Color.muted)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Color.muted.opacity(0.5))
            Text(store.page.rawValue)
            Spacer()
            if store.isImporting { ProgressView().controlSize(.small); Text("Indexing…").foregroundStyle(Color.muted) }
            Tag(text: "LOCAL SEARCH", icon: "lock.shield")
        }.font(.system(size: 11)).padding(.horizontal, 28).frame(height: 64)
    }
    private func banner(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
            Text(text).textSelection(.enabled)
            Spacer()
            Button { if isError { store.error = nil } else { store.notice = nil } } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }.font(.system(size: 12)).foregroundStyle(isError ? Color.orange : Color.mint)
            .padding(14).background((isError ? Color.orange : Color.mint).opacity(0.08))
    }
}
