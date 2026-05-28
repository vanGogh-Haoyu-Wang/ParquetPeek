import SwiftUI
import ParquetPeekCore

struct DetailView: View {
    @Bindable var store: ParquetBrowserStore

    var body: some View {
        VStack(spacing: 0) {
            if let document = store.selectedDocument {
                HeaderView(store: store, document: document)
                Divider()
                DataGridView(
                    columns: store.rowPage.columns,
                    rows: store.filteredRows,
                    rowOffset: store.rowPage.offset,
                    isLoading: store.isLoading
                )
                Divider()
                PagingBarView(store: store, document: document)
            } else {
                ContentUnavailableView(
                    "Open a Parquet File",
                    systemImage: "tablecells.badge.ellipsis",
                    description: Text("Use the toolbar button or drag a .parquet file into this window.")
                )
            }
        }
    }
}

private struct HeaderView: View {
    @Bindable var store: ParquetBrowserStore
    let document: ParquetDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.displayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(document.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                SummaryPill(title: "Rows", value: Formatters.rows(document.metadata.rowCount))
                SummaryPill(title: "Columns", value: "\(document.metadata.columnCount)")
                SummaryPill(title: "Groups", value: "\(document.metadata.rowGroupCount)")
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search current page", text: $store.searchText)
                    .textFieldStyle(.plain)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(16)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
        .frame(minWidth: 72, alignment: .trailing)
    }
}

private struct DataGridView: View {
    let columns: [String]
    let rows: [[String]]
    let rowOffset: Int64
    let isLoading: Bool

    private let rowNumberWidth: CGFloat = 72
    private let columnWidth: CGFloat = 180

    var body: some View {
        ZStack {
            if columns.isEmpty {
                ContentUnavailableView(
                    "No Rows Loaded",
                    systemImage: "tablecells",
                    description: Text("Select columns in the sidebar and load a page.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            HeaderCell("#", width: rowNumberWidth)
                            ForEach(columns, id: \.self) { column in
                                HeaderCell(column, width: columnWidth)
                            }
                        }

                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 0) {
                                BodyCell("\(rowOffset + Int64(index) + 1)", width: rowNumberWidth, isIndex: true)
                                ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, _ in
                                    BodyCell(row.indices.contains(columnIndex) ? row[columnIndex] : "", width: columnWidth)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }

            if isLoading {
                ProgressView("Reading page...")
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct HeaderCell: View {
    let title: String
    let width: CGFloat

    init(_ title: String, width: CGFloat) {
        self.title = title
        self.width = width
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: width, height: 30, alignment: .leading)
            .background(Color(nsColor: .tertiaryLabelColor).opacity(0.08))
            .border(Color(nsColor: .separatorColor), width: 0.5)
    }
}

private struct BodyCell: View {
    let value: String
    let width: CGFloat
    var isIndex = false

    init(_ value: String, width: CGFloat, isIndex: Bool = false) {
        self.value = value
        self.width = width
        self.isIndex = isIndex
    }

    var body: some View {
        Text(value.isEmpty ? "NULL" : value)
            .font(.caption.monospaced())
            .foregroundStyle(value.isEmpty ? .tertiary : (isIndex ? .secondary : .primary))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: width, height: 28, alignment: .leading)
            .background(isIndex ? Color(nsColor: .quaternaryLabelColor).opacity(0.08) : Color.clear)
            .border(Color(nsColor: .separatorColor), width: 0.5)
            .textSelection(.enabled)
    }
}

private struct PagingBarView: View {
    @Bindable var store: ParquetBrowserStore
    let document: ParquetDocument

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.previousPage()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(store.pageOffset == 0 || store.isLoading)

            Button {
                store.nextPage()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(store.pageOffset + Int64(store.pageSize) >= document.metadata.rowCount || store.isLoading)

            Stepper("Page size: \(store.pageSize)", value: $store.pageSize, in: 100...10_000, step: 100)
                .frame(width: 190)
                .disabled(store.isLoading)
                .onChange(of: store.pageSize) {
                    store.reloadPage()
                }

            Spacer()

            Text(Formatters.pageRange(
                offset: store.rowPage.offset,
                count: store.filteredRows.count,
                total: document.metadata.rowCount
            ))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
