import SwiftUI
import RagCore

struct ConnectionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: AIConnection?
    @State private var deleteCandidate: AIConnection?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    SectionTitle(eyebrow: "Make it yours", title: "Your AI, your choice", subtitle: "Connect a local model or a cloud provider. Switch whenever you need.")
                    Spacer()
                    Button { editing = AIConnection() } label: { Label("Add connection", systemImage: "plus") }.buttonStyle(PrimaryButton()).disabled(store.readOnly)
                }
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield").font(.system(size: 22)).foregroundStyle(Color.mint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Local knowledge. A connection you control.").font(.system(size: 13, weight: .medium))
                        Text("Indexing and search happen on your Mac. Questions, relevant excerpts, and recent chat messages go to the selected endpoint. Choose a local-only model server to keep inference on this Mac. API keys are stored in macOS Keychain.")
                            .font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(5)
                    }
                }.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(Color.mint.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mint.opacity(0.13)))
                VStack(spacing: 12) {
                    ForEach(store.state.connections) { connection in
                        connectionCard(connection)
                    }
                }
                if store.state.connections.isEmpty {
                    Text("Add your first connection to start asking questions.").font(.system(size: 14)).foregroundStyle(Color.muted).padding(.vertical, 35)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("RETRIEVAL").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Color.muted)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Source excerpts per answer").font(.system(size: 13, weight: .medium))
                            Text("More excerpts add context, but use a larger model context window.").font(.system(size: 11)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Picker("Excerpts", selection: $store.state.excerptCount) {
                            ForEach([3, 6, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                        }.labelsHidden().frame(width: 80).disabled(store.readOnly)
                    }
                    Text("Search method: local BM25 keyword ranking. An embedding model is not required. Use names and terms from your files for best results.")
                        .font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(4)
                }.padding(22).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 10) {
                    Text("GETTING STARTED WITH LOCAL AI").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Color.muted)
                    Text("Run Ollama or LM Studio, download a chat model, and start its local server. Edit the connection below, load its models, select one, then test and save.")
                        .font(.system(size: 12)).foregroundStyle(Color.muted).lineSpacing(5)
                }
            }.padding(32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { connection in ConnectionEditor(initial: connection).environmentObject(store) }
        .onChange(of: store.state.excerptCount) { _, _ in store.persist() }
        .confirmationDialog("Delete this connection and its saved API key?", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            Button("Delete connection", role: .destructive) {
                if let deleteCandidate { do { try store.deleteConnection(deleteCandidate.id) } catch { store.error = error.localizedDescription } }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        }
    }
    private func connectionCard(_ connection: AIConnection) -> some View {
        let active = store.activeConnection?.id == connection.id
        return HStack(spacing: 16) {
            Image(systemName: connection.isLocal ? "desktopcomputer" : "cloud")
                .font(.system(size: 24, weight: .light)).foregroundStyle(Color.mint)
                .frame(width: 49, height: 49).background(Color.mint.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(connection.name).font(.system(size: 14, weight: .semibold)); if active { Tag(text: "Selected") } }
                Text(connection.model.isEmpty ? "Choose a model to finish setup" : connection.model).font(.system(size: 11)).foregroundStyle(connection.model.isEmpty ? Color.orange : Color.muted)
                Text(connection.baseURL).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(1)
            }
            Spacer()
            if !active { Button("Use") { store.selectConnection(connection.id) }.buttonStyle(QuietButton()).disabled(store.readOnly) }
            Button("Edit") { editing = connection }.buttonStyle(QuietButton()).disabled(store.readOnly)
            Menu { Button("Delete connection…", role: .destructive) { deleteCandidate = connection } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(store.readOnly)
        }.padding(20).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Color.mint.opacity(0.35) : Color.line))
    }
}

struct ConnectionEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var connection: AIConnection
    @State private var key = ""
    @State private var models: [String] = []
    @State private var status: String?
    @State private var isError = false
    @State private var busy = false
    @State private var keyReadable = true
    @State private var work: Task<Void, Never>?
    init(initial: AIConnection) { _connection = State(initialValue: initial) }
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI connection").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Choose where your questions are answered.").font(.system(size: 12)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Color.muted)
            }
            VStack(alignment: .leading, spacing: 15) {
                field("Provider") {
                    Picker("Provider", selection: $connection.kind) { ForEach(ProviderKind.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
                }
                field("Connection name") { TextField("My local model", text: $connection.name) }
                field("API base URL") { TextField("http://localhost:11434/v1", text: $connection.baseURL) }
                Text("Include /v1 when required by your server. Remote endpoints must use HTTPS.").font(.system(size: 10)).foregroundStyle(Color.muted).padding(.top, -8)
                field(connection.kind.needsKey ? "API key" : "API key (optional)") { SecureField("Stored securely in Keychain", text: $key) }
                field("Model ID") {
                    HStack {
                        TextField("Enter a model ID or load available models", text: $connection.model)
                        Button("Load models") { loadModels() }.disabled(busy || !keyReadable)
                    }
                }
                if !models.isEmpty {
                    Picker("Available models", selection: $connection.model) {
                        Text("Choose a model…").tag("")
                        if !connection.model.isEmpty && !models.contains(connection.model) { Text(connection.model).tag(connection.model) }
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }.font(.system(size: 12))
                }
            }.textFieldStyle(.roundedBorder).disabled(busy)
            if let status {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                    Text(status).textSelection(.enabled)
                }.font(.system(size: 12)).foregroundStyle(isError ? .orange : Color.mint)
            }
            Text("The connection test sends a short ‘OK’ prompt to this endpoint and may incur a small provider charge. It does not send your documents.")
                .font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(4)
            Divider().overlay(Color.line)
            HStack {
                Button { test() } label: {
                    HStack { if busy { ProgressView().controlSize(.small) }; Text(busy ? "Connecting…" : "Test connection") }
                }.buttonStyle(QuietButton()).disabled(busy || connection.model.isEmpty || !keyReadable)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButton())
                Button("Save & use") { save() }.buttonStyle(PrimaryButton()).disabled(busy || !keyReadable || connection.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(29).frame(width: 570).background(Color.canvas)
        .onAppear {
            do { key = try KeychainStore.read(id: connection.id) }
            catch { keyReadable = false; show(error.localizedDescription, error: true) }
        }
        .onDisappear { work?.cancel() }
        .onChange(of: connection.kind) { _, kind in
            connection.name = kind.rawValue; connection.baseURL = kind.defaultURL; connection.model = ""
            key = ""; models = []; status = nil
        }
        .onChange(of: connection.baseURL) { _, _ in models = []; status = nil }
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.muted); content() }
    }
    private func show(_ text: String, error: Bool = false) { status = text; isError = error }
    private func loadModels() {
        busy = true; status = nil
        work = Task {
            defer { busy = false }
            do {
                models = try await AIClient().models(connection: connection, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
                if models.isEmpty { show("No models found. Download or load a chat model on the server first.", error: true) }
                else { if connection.model.isEmpty { connection.model = models[0] }; show("Found \(models.count) models. Choose a chat model from the list.") }
            } catch { if !Task.isCancelled { show(error.localizedDescription, error: true) } }
        }
    }
    private func test() {
        busy = true; status = nil
        work = Task {
            defer { busy = false }
            do { show(try await AIClient().test(connection: connection, key: key.trimmingCharacters(in: .whitespacesAndNewlines))) }
            catch { if !Task.isCancelled { show(error.localizedDescription, error: true) } }
        }
    }
    private func save() {
        do {
            connection.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.model = connection.model.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.saveConnection(connection, key: key); dismiss()
        } catch { show(error.localizedDescription, error: true) }
    }
}
