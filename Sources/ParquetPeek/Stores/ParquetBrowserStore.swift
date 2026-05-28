import AppKit
import Foundation
import Observation
import ParquetPeekCore

@MainActor
@Observable
final class ParquetBrowserStore {
    var documents: [ParquetDocument] = []
    var selection: BrowserSelection?
    var selectedDocumentID: UUID?
    var rowPage = RowPage(offset: 0, limit: 1000, cancelled: false, columns: [], rows: [])
    var pageOffset: Int64 = 0
    var pageSize = 1000
    var selectedColumnNames: Set<String> = []
    var searchText = ""
    var isLoading = false
    var statusMessage = "Drop a .parquet file or choose File > Open."
    var errorMessage: String?

    private let service: ParquetService
    private var loadTask: Task<Void, Never>?

    init(service: ParquetService) {
        self.service = service
    }

    var selectedDocument: ParquetDocument? {
        guard let selectedDocumentID else {
            return documents.first
        }
        return documents.first { $0.id == selectedDocumentID }
    }

    var filteredRows: [[String]] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return rowPage.rows
        }
        return rowPage.rows.filter { row in
            row.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "parquet")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }
            Task { @MainActor in
                for url in panel.urls {
                    await self?.open(url: url)
                }
            }
        }
    }

    func open(url: URL) async {
        guard url.pathExtension.lowercased() == "parquet" else {
            errorMessage = ParquetBrowserError.unsupportedFile(url).localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = "Opening \(url.lastPathComponent)..."

        do {
            let handle = try await service.openFile(at: url)
            async let metadataTask = service.loadMetadata(handle: handle)
            async let schemaTask = service.loadSchema(handle: handle)
            let (metadata, schema) = try await (metadataTask, schemaTask)
            let document = ParquetDocument(
                url: url,
                handle: handle,
                metadata: metadata,
                columns: schema
            )
            documents.append(document)
            selectedDocumentID = document.id
            selection = .file(document.id)
            selectedColumnNames = Set(document.columns.prefix(24).map(\.name))
            pageOffset = 0
            statusMessage = "Opened \(document.displayName)."
            await loadCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Open failed."
        }

        isLoading = false
    }

    func select(document id: UUID) {
        selectedDocumentID = id
        selection = .file(id)
        if let document = selectedDocument {
            selectedColumnNames = Set(document.columns.prefix(24).map(\.name))
            pageOffset = 0
            Task { await loadCurrentPage() }
        }
    }

    func toggleColumn(_ column: ParquetColumn) {
        if selectedColumnNames.contains(column.name) {
            selectedColumnNames.remove(column.name)
        } else {
            selectedColumnNames.insert(column.name)
        }
        pageOffset = PageMath.clampedOffset(pageOffset, totalRows: selectedDocument?.metadata.rowCount ?? 0)
        Task { await loadCurrentPage() }
    }

    func nextPage() {
        guard let document = selectedDocument else {
            return
        }
        pageOffset = PageMath.nextOffset(current: pageOffset, pageSize: pageSize, totalRows: document.metadata.rowCount)
        Task { await loadCurrentPage() }
    }

    func previousPage() {
        pageOffset = PageMath.previousOffset(current: pageOffset, pageSize: pageSize)
        Task { await loadCurrentPage() }
    }

    func reloadPage() {
        Task { await loadCurrentPage() }
    }

    func cancelLoading() {
        guard let document = selectedDocument else {
            return
        }
        service.cancel(handle: document.handle)
        loadTask?.cancel()
        isLoading = false
        statusMessage = "Cancelled."
    }

    func closeSelectedDocument() {
        guard let id = selectedDocumentID else {
            return
        }
        closeDocument(id: id)
    }

    func closeDocument(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wasSelected = selectedDocumentID == id
        service.closeFile(handle: documents[index].handle)
        documents.remove(at: index)
        if wasSelected {
            selectedDocumentID = documents.indices.contains(index)
                ? documents[index].id
                : documents.last?.id
            selection = selectedDocumentID.map { .file($0) }
            pageOffset = 0
            searchText = ""
            rowPage = RowPage(offset: 0, limit: pageSize, cancelled: false, columns: [], rows: [])
            if let document = selectedDocument {
                selectedColumnNames = Set(document.columns.prefix(24).map(\.name))
                Task { await loadCurrentPage() }
            } else {
                selectedColumnNames = []
                statusMessage = "Drop a .parquet file or choose File > Open."
            }
        }
    }

    func loadCurrentPage() async {
        loadTask?.cancel()
        guard let document = selectedDocument else {
            rowPage = RowPage(offset: 0, limit: pageSize, cancelled: false, columns: [], rows: [])
            statusMessage = "Drop a .parquet file or choose File > Open."
            return
        }

        let columns = selectedColumnNames.isEmpty
            ? document.columns.prefix(24).map(\.name)
            : document.columns.filter { selectedColumnNames.contains($0.name) }.map(\.name)
        let offset = PageMath.clampedOffset(pageOffset, totalRows: document.metadata.rowCount)
        pageOffset = offset
        isLoading = true
        errorMessage = nil
        statusMessage = "Reading rows..."

        let task = Task { [service] in
            do {
                let page = try await service.readRows(
                    handle: document.handle,
                    offset: offset,
                    limit: pageSize,
                    columns: columns
                )
                await MainActor.run {
                    self.rowPage = page
                    self.statusMessage = Formatters.pageRange(
                        offset: page.offset,
                        count: page.rows.count,
                        total: document.metadata.rowCount
                    )
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "Read failed."
                    self.isLoading = false
                }
            }
        }
        loadTask = task
        await task.value
    }
}
