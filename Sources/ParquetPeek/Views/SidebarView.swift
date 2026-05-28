import SwiftUI
import ParquetPeekCore

struct SidebarView: View {
    @Bindable var store: ParquetBrowserStore

    var body: some View {
        List(selection: $store.selection) {
            if store.documents.isEmpty {
                ContentUnavailableView(
                    "No Parquet File",
                    systemImage: "tablecells",
                    description: Text("Open or drop a .parquet file.")
                )
            }

            ForEach(store.documents) { document in
                Section {
                    HStack(spacing: 6) {
                        Button {
                            store.select(document: document.id)
                        } label: {
                            Label(document.displayName, systemImage: "doc.richtext")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 4)

                        Button {
                            store.closeDocument(id: document.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close file")
                    }
                    .tag(BrowserSelection.file(document.id))

                    MetadataSummaryView(document: document)

                    DisclosureGroup("Columns") {
                        ForEach(document.columns) { column in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { store.selectedColumnNames.contains(column.name) },
                                    set: { _ in store.toggleColumn(column) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(column.name)
                                        .lineLimit(1)
                                    Text("\(column.physicalType) / \(column.logicalType)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(BrowserSelection.column(document.id, column.index))
                        }
                    }

                    DisclosureGroup("Row Groups") {
                        ForEach(document.metadata.rowGroups) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Group \(group.index)")
                                Text("\(Formatters.rows(group.rowCount)) rows, \(Formatters.bytes(group.totalByteSize))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(BrowserSelection.rowGroup(document.id, group.index))
                        }
                    }
                } header: {
                    Text(document.displayName)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(store.statusMessage)
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(.bar)
        }
    }
}

private struct MetadataSummaryView: View {
    let document: ParquetDocument

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Rows")
                    .foregroundStyle(.secondary)
                Text(Formatters.rows(document.metadata.rowCount))
            }
            GridRow {
                Text("Columns")
                    .foregroundStyle(.secondary)
                Text("\(document.metadata.columnCount)")
            }
            GridRow {
                Text("Row Groups")
                    .foregroundStyle(.secondary)
                Text("\(document.metadata.rowGroupCount)")
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
    }
}
