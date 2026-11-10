import SwiftUI
import AppKit
import RagCore

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @FocusState private var composerFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        Button("All sources") { store.selectedSourceIDs = [] }
                        Divider()
                        ForEach(store.state.sources) { source in
                            Button {
                                if store.selectedSourceIDs.contains(source.id) { store.selectedSourceIDs.remove(source.id) }
                                else { store.selectedSourceIDs.insert(source.id) }
                            } label: {
                                Label(source.name, systemImage: store.selectedSourceIDs.contains(source.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } label: {
                        Label(store.selectedSourceIDs.isEmpty ? "All knowledge" : "\(store.selectedSourceIDs.count) selected sources", systemImage: "line.3.horizontal.decrease.circle")
                    }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).foregroundStyle(Color.muted)
                    Spacer()
                    if let connection = store.activeConnection {
                        Text(connection.model.isEmpty ? "No model selected" : connection.model).font(.system(size: 10)).foregroundStyle(Color.muted).lineLimit(1)
                    }
                }.padding(.horizontal, 32).padding(.vertical, 18)
                if store.currentConversation?.messages.isEmpty != false {
                    welcome.frame(maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 27) {
                                ForEach(store.currentConversation?.messages ?? []) { message in
                                    MessageView(message: message).id(message.id)
                                }
                                if store.isAnswering {
                                    HStack(spacing: 10) {
                                        ProgressView().controlSize(.small)
                                        Text("Reading relevant excerpts and composing an answer…").font(.system(size: 12)).foregroundStyle(Color.muted)
                                    }.padding(.leading, 42)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }.padding(.horizontal, 36).padding(.vertical, 25).frame(maxWidth: 900).frame(maxWidth: .infinity)
                        }
                        .onChange(of: store.currentConversation?.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                        .onChange(of: store.isAnswering) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                        .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                composer.padding(.horizontal, 32).padding(.bottom, 19)
            }.frame(maxWidth: .infinity)
            if let citation = store.shownCitation {
                citationPanel(citation).frame(width: 285).transition(.move(edge: .trailing))
            }
        }
    }
    private var welcome: some View {
        VStack(spacing: 21) {
            Spacer(minLength: 15)
            BrandMark(size: 58).shadow(color: .mint.opacity(0.12), radius: 35)
            VStack(spacing: 12) {
                Text("Your knowledge.\nA clearer answer.")
                    .font(.system(size: 38, weight: .medium, design: .rounded)).multilineTextAlignment(.center).lineSpacing(3)
                Text(store.state.documents.isEmpty ? "Bring your documents together. Ask questions.\nFind answers grounded in your own knowledge." : "Ask a question across your documents.\nEvery answer starts with your sources.")
                    .font(.system(size: 13)).foregroundStyle(Color.muted).multilineTextAlignment(.center).lineSpacing(5)
            }
            if store.state.documents.isEmpty {
                HStack(spacing: 10) {
                    Button { store.chooseFiles(folder: false) } label: { Label("Add documents", systemImage: "plus") }.buttonStyle(PrimaryButton())
                    Button { store.chooseFiles(folder: true) } label: { Label("Add a folder", systemImage: "folder.badge.plus") }.buttonStyle(QuietButton())
                }.padding(.top, 6).disabled(store.isImporting || store.readOnly)
                HStack(spacing: 14) {
                    Text("PDF"); Text("DOCX"); Text("MARKDOWN"); Text("TEXT + MORE")
                }.font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(Color.muted).padding(.top, 2)
            } else {
                VStack(spacing: 8) {
                    suggestion("Give me an overview of my documents", icon: "text.alignleft")
                    suggestion("What are the key points in these documents?", icon: "sparkle.magnifyingglass")
                }.frame(maxWidth: 380).padding(.top, 5)
            }
            Spacer(minLength: 25)
            HStack(spacing: 24) {
                Label("Local document search", systemImage: "internaldrive")
                Label("Your choice of AI", systemImage: "slider.horizontal.3")
                Label("Traceable sources", systemImage: "quote.bubble")
            }.font(.system(size: 10)).foregroundStyle(Color.muted).padding(.bottom, 24)
        }.padding(.horizontal, 25)
    }
    private func suggestion(_ text: String, icon: String) -> some View {
        Button { store.ask(text) } label: {
            HStack { Image(systemName: icon).foregroundStyle(Color.mint); Text(text); Spacer(); Image(systemName: "arrow.up.left").foregroundStyle(Color.muted) }
                .font(.system(size: 12)).padding(14).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.line))
        }.buttonStyle(.plain).disabled(store.isAnswering || store.isImporting)
    }
    private var composer: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 13) {
                TextField(store.state.documents.isEmpty ? "Add your first document to get started…" : "Ask a question about your documents…", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(2...5).focused($composerFocused)
                    .onSubmit { store.ask() }.disabled(store.readOnly)
                HStack {
                    Button { store.chooseFiles(folder: false) } label: { Image(systemName: "plus.circle").font(.system(size: 18)) }
                        .buttonStyle(.plain).foregroundStyle(Color.muted).help("Add documents").disabled(store.isImporting || store.readOnly)
                    Text(store.selectedSourceIDs.isEmpty ? "\(store.state.documents.count) documents in context" : "Searching selected sources")
                        .font(.system(size: 10)).foregroundStyle(Color.muted)
                    Spacer()
                    if store.isAnswering {
                        Button { store.stopAnswer() } label: { Image(systemName: "stop.fill").frame(width: 31, height: 31).background(Color.raised).clipShape(RoundedRectangle(cornerRadius: 8)) }
                            .buttonStyle(.plain).help("Stop response")
                    } else {
                        Text("⌘ ↵").font(.system(size: 10)).foregroundStyle(Color.muted)
                        Button { store.ask() } label: {
                            Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.canvas)
                                .frame(width: 31, height: 31).background(store.canAsk ? Color.mint : Color.muted.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(!store.canAsk).keyboardShortcut(.return, modifiers: .command).help("Ask question")
                    }
                }
            }.padding(17).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(composerFocused ? Color.mint.opacity(0.4) : Color.line))
            Text(store.activeConnection?.isLocal == true ? "Relevant excerpts and recent chat messages are sent to your local AI server. Verify answers against sources." : "Relevant excerpts and recent chat messages are sent to your selected AI provider. Verify answers against sources.")
                .font(.system(size: 9)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: 900).frame(maxWidth: .infinity)
    }
    private func citationPanel(_ citation: Citation) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("SOURCE EXCERPT").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Color.muted)
                Spacer()
                Button { store.shownCitation = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Label(citation.documentName, systemImage: "doc.text").font(.system(size: 14, weight: .medium)).lineLimit(3)
            Tag(text: citation.page.map { "Source \(citation.number) · Page \($0)" } ?? "Source \(citation.number)")
            ScrollView { Text(citation.excerpt).font(.system(size: 12)).lineSpacing(6).foregroundStyle(Color.primary.opacity(0.85)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Text("Saved excerpt from the time of this answer. The original file may have changed.").font(.system(size: 10)).foregroundStyle(Color.muted)
            Button { store.openCitation(citation) } label: { Label("Open original file", systemImage: "arrow.up.right.square") }.buttonStyle(QuietButton())
        }.padding(22).background(Color.sidebar).overlay(alignment: .leading) { Rectangle().fill(Color.line).frame(width: 1) }
    }
}

struct MessageView: View {
    @EnvironmentObject private var store: AppStore
    let message: ChatMessage
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            if message.role == "assistant" { BrandMark(size: 29) }
            else { Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.muted).frame(width: 29, height: 29).background(Color.raised).clipShape(RoundedRectangle(cornerRadius: 8)) }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(message.role == "assistant" ? "MyRagAI" : "You").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .font(.system(size: 10)).foregroundStyle(Color.muted).buttonStyle(.plain).help("Copy message")
                }.padding(.top, 5)
                Text(.init(message.text)).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).tint(.mint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !message.citations.isEmpty {
                    Text("RETRIEVED SOURCES").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(Color.muted).padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 7) {
                        ForEach(message.citations) { citation in
                            Button { withAnimation(.easeInOut(duration: 0.2)) { store.shownCitation = citation } } label: {
                                HStack(spacing: 7) {
                                    Text("\(citation.number)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.mint).frame(width: 20, height: 20).background(Color.mint.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(citation.documentName).font(.system(size: 10)).lineLimit(1)
                                    if let page = citation.page { Text("p.\(page)").font(.system(size: 9)).foregroundStyle(Color.muted) }
                                    Spacer(minLength: 0)
                                }.padding(8).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.line))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let provider = message.providerLabel { Text(provider).font(.system(size: 9)).foregroundStyle(Color.muted) }
            }
        }
    }
}
