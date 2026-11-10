import SwiftUI
import AppKit
import RagCore

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var sourceToRemove: Source?
    @State private var preview: Citation?
    @State private var showWarnings = true
    @State private var showImportOptions = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    SectionTitle(eyebrow: "Your sources", title: "Knowledge library", subtitle: "A home for the documents you want to think with.")
                    Spacer(minLength: 10)
                    Button { showImportOptions.toggle() } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "plus")
                            Text("Add knowledge")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }.buttonStyle(PrimaryButton())
                        .fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                        .disabled(store.isImporting || store.readOnly)
                        .popover(isPresented: $showImportOptions, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 7) {
                                importOption("Add documents", detail: "Choose PDF, DOCX, or text files", icon: "doc.badge.plus", folder: false)
                                importOption("Add a folder", detail: "Include supported files inside it", icon: "folder.badge.plus", folder: true)
                            }.padding(10).frame(width: 285).background(Color.panel)
                        }
                }
                HStack(spacing: 13) {
                    metric("\(store.state.sources.count)", label: "Connected sources", icon: "folder")
                    metric("\(store.state.documents.count)", label: "Indexed documents", icon: "doc.text")
                    metric("\(store.totalChunks)", label: "Searchable excerpts", icon: "text.magnifyingglass")
                }
                if store.isImporting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(store.importStatus).font(.system(size: 12))
                        Spacer()
                        Button("Cancel") { store.cancelImport() }.buttonStyle(.plain).font(.caption)
                    }.padding(16).background(Color.mint.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 9))
                }
                if !store.importWarnings.isEmpty {
                    DisclosureGroup(isExpanded: $showWarnings) {
                        ScrollView { VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(store.importWarnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.font(.system(size: 11)).textSelection(.enabled).padding(.top, 9) }.frame(maxHeight: 130)
                    } label: { Label("Import notes (\(store.importWarnings.count))", systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .medium)) }
                        .foregroundStyle(.orange).padding(15).background(Color.orange.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 9))
                }
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.muted)
                    TextField("Search inside your documents…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Color.muted) }
                    Spacer()
                    if query.isEmpty {
                        Button { store.rescan(store.state.sources) } label: { Label("Rescan all", systemImage: "arrow.clockwise") }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.muted).disabled(store.isImporting || store.state.sources.isEmpty || store.readOnly)
                    }
                }.padding(14).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.line))
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResults
                } else if store.state.sources.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("SOURCE"); Spacer(); Text("STATUS")
                        }.font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(Color.muted).padding(.horizontal, 19).padding(.vertical, 15)
                        Divider().overlay(Color.line)
                        ForEach(store.state.sources) { source in
                            sourceRow(source)
                            if source.id != store.state.sources.last?.id { Divider().overlay(Color.line).padding(.leading, 64) }
                        }
                    }.background(Color.panel.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line))
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(Color.mint)
                    Text("Your original files stay where they are. Use Rescan after changing a file or folder. PDF, DOCX, RTF and UTF-8/UTF-16 text formats are supported, up to 20 MB per file and 500 files per folder. Scanned PDFs need OCR before import.")
                        .font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(4)
                }.padding(.top, 3)
            }.padding(32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .task(id: query) {
            if query.isEmpty { hits = []; return }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let results = await store.search(query)
            if !Task.isCancelled { hits = results }
        }
        .onChange(of: store.isImporting) { _, value in
            if !value && !query.isEmpty { Task { hits = await store.search(query) } }
        }
        .confirmationDialog("Remove this source from MyRagAI?", isPresented: Binding(get: { sourceToRemove != nil }, set: { if !$0 { sourceToRemove = nil } }), titleVisibility: .visible) {
            Button("Remove source", role: .destructive) { if let sourceToRemove { store.removeSource(sourceToRemove) }; sourceToRemove = nil }
            Button("Cancel", role: .cancel) { sourceToRemove = nil }
        } message: { Text("Its indexed text will be removed. Your original files and excerpts saved in past conversations will be kept.") }
        .sheet(item: $preview) { citation in
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text(citation.documentName).font(.title3.bold()); Spacer(); Button("Done") { preview = nil } }
                if let page = citation.page { Tag(text: "Page \(page)") }
                ScrollView { Text(citation.excerpt).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button { store.openCitation(citation) } label: { Label("Open original", systemImage: "arrow.up.right.square") }.buttonStyle(QuietButton())
            }.padding(25).frame(width: 580, height: 460).background(Color.canvas)
        }
    }
    private func importOption(_ title: String, detail: String, icon: String, folder: Bool) -> some View {
        Button {
            showImportOptions = false
            // Let the popover close before presenting the native file picker.
            DispatchQueue.main.async { store.chooseFiles(folder: folder) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.mint).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary)
                    Text(detail).font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(QuietButton())
    }
    private func metric(_ value: String, label: String, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 9) {
                Text(value).font(.system(size: 27, weight: .medium, design: .rounded))
                Text(label).font(.system(size: 10)).foregroundStyle(Color.muted)
            }
            Spacer()
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.mint.opacity(0.7))
        }.padding(20).frame(maxWidth: .infinity).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.line))
    }
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Color.mint)
            Text("Make room for what you know").font(.system(size: 19, weight: .medium, design: .rounded))
            Text("Add individual documents or connect an entire folder.\nYour searchable index is built right here on your Mac.")
                .font(.system(size: 12)).foregroundStyle(Color.muted).multilineTextAlignment(.center).lineSpacing(5)
            HStack {
                Button("Add documents") { store.chooseFiles(folder: false) }.buttonStyle(PrimaryButton())
                Button("Add folder") { store.chooseFiles(folder: true) }.buttonStyle(QuietButton())
            }.disabled(store.isImporting || store.readOnly)
        }.frame(maxWidth: .infinity).padding(.vertical, 58).background(Color.panel.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5])).foregroundStyle(Color.line))
    }
    private func sourceRow(_ source: Source) -> some View {
        let docs = store.state.documents.filter { $0.sourceID == source.id }
        return HStack(spacing: 14) {
            Image(systemName: source.isFolder ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 18)).foregroundStyle(source.isFolder ? Color.mint : Color.muted)
                .frame(width: 33, height: 39).background(Color.raised).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 6) {
                Text(source.name).font(.system(size: 12, weight: .medium))
                Text(source.path).font(.system(size: 10)).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle).help(source.path)
                HStack(spacing: 7) {
                    Text("\(docs.count) documents")
                    if let indexed = source.lastIndexedAt { Text("·"); Text(indexed, style: .relative); Text("ago") }
                }.font(.system(size: 9)).foregroundStyle(Color.muted)
            }
            Spacer()
            Tag(text: docs.isEmpty ? "No text" : "Indexed", icon: docs.isEmpty ? "minus.circle" : "checkmark.circle", color: docs.isEmpty ? .orange : .mint)
            Menu {
                Button("Rescan source") { store.rescan([source]) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.path)]) }
                Divider()
                Button("Remove source…", role: .destructive) { sourceToRemove = source }
            } label: { Image(systemName: "ellipsis").padding(5) }.menuStyle(.borderlessButton).fixedSize().disabled(store.isImporting || store.readOnly)
        }.padding(17)
    }
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(hits.count) matching excerpts").font(.system(size: 11)).foregroundStyle(Color.muted)
            if hits.isEmpty { Text("No matching text found. Try a specific word or phrase from your documents.").font(.system(size: 13)).foregroundStyle(Color.muted).padding(.vertical, 35) }
            ForEach(hits) { hit in
                Button { preview = hit.citation(number: 1) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(hit.document.name, systemImage: "doc.text").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.mint)
                            Spacer()
                            if let page = hit.chunk.page { Text("Page \(page)").font(.system(size: 10)).foregroundStyle(Color.muted) }
                        }
                        Text(hit.chunk.text).font(.system(size: 12)).lineSpacing(4).lineLimit(3).foregroundStyle(Color.primary.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(17).background(Color.panel).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line))
                }.buttonStyle(.plain)
            }
        }
    }
}
