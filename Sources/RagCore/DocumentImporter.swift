import Foundation
import PDFKit
import AppKit

public struct ImportResult: Sendable {
    public var documents: [IndexedDocument]
    public var warnings: [String]
    public var scannedCount: Int
}

public enum DocumentImporter {
    public static let extensions: Set<String> = ["pdf", "txt", "md", "markdown", "csv", "tsv", "json", "log", "yaml", "yml", "xml", "html", "rtf", "docx"]
    public static let maxFileBytes = 20 * 1024 * 1024
    public static let maxFiles = 500

    public static func index(source: Source) throws -> ImportResult {
        let root = URL(fileURLWithPath: source.path)
        var url = root
        if let bookmark = source.bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale) { url = resolved }
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { throw RagError.message("\(source.name) is no longer available. Reconnect the drive or add its new location.") }
        var files: [URL] = []
        var warnings: [String] = []
        if source.isFolder {
            guard let enumerator = FileManager.default.enumerator(at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { failingURL, _ in
                    warnings.append("Could not read \(failingURL.lastPathComponent). Check its permissions.")
                    return true
                }) else { throw RagError.message("This folder could not be read.") }
            for case let file as URL in enumerator {
                try Task.checkCancellation()
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values?.isRegularFile == true && extensions.contains(file.pathExtension.lowercased()) {
                    if files.count >= maxFiles { warnings.append("Folder limit reached: only the first \(maxFiles) supported files were indexed. Add smaller subfolders for the rest."); break }
                    files.append(file)
                }
            }
        } else { files = [url] }
        var documents: [IndexedDocument] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            do {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard (values.fileSize ?? 0) <= maxFileBytes else { throw RagError.message("Files over 20 MB are not supported yet.") }
                guard extensions.contains(file.pathExtension.lowercased()) else { throw RagError.message("Unsupported file format.") }
                let chunks = try extract(file)
                guard !chunks.isEmpty else { throw RagError.message("No readable text. Scanned PDFs need OCR first.") }
                if chunks.count > 2000 { throw RagError.message("Document exceeds the 2,000-excerpt limit. Split it into smaller files.") }
                documents.append(IndexedDocument(sourceID: source.id, path: file.path,
                    modifiedAt: values.contentModificationDate ?? Date(), chunks: chunks))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        if files.isEmpty { warnings.append("No supported documents were found in \(source.name).") }
        return ImportResult(documents: documents, warnings: warnings, scannedCount: files.count)
    }

    private static func extract(_ url: URL) throws -> [TextChunk] {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url), !document.isLocked else { throw RagError.message("This PDF is locked or unreadable.") }
            guard document.pageCount <= 1000 else { throw RagError.message("PDFs over 1,000 pages must be split into smaller files.") }
            var chunks: [TextChunk] = []
            for page in 0..<document.pageCount {
                try Task.checkCancellation()
                chunks += Chunker.split(document.page(at: page)?.string ?? "", page: page + 1)
                if chunks.count > 2000 { throw RagError.message("Document exceeds the 2,000-excerpt limit. Split it into smaller files.") }
            }
            return chunks
        case "rtf", "docx":
            let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "rtf" ? .rtf : .officeOpenXML
            let document = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            return Chunker.split(document.string)
        default:
            let data = try Data(contentsOf: url)
            // Only decode UTF-16 when marked with a BOM; binary files must not silently become text.
            let isUTF16 = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
            guard let text = String(data: data, encoding: isUTF16 ? .utf16 : .utf8), !text.contains("\0") else {
                throw RagError.message("Save this text file as UTF-8 or UTF-16 with a byte-order mark and import again.")
            }
            return Chunker.split(text)
        }
    }
}
