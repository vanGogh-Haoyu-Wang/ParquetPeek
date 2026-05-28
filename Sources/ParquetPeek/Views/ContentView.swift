import SwiftUI
import UniformTypeIdentifiers
import ParquetPeekCore

struct ContentView: View {
    @Bindable var store: ParquetBrowserStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            DetailView(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentOpenPanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Button {
                    store.reloadPage()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(store.selectedDocument == nil || store.isLoading)

                Button {
                    store.closeSelectedDocument()
                } label: {
                    Label("Close File", systemImage: "xmark.circle")
                }
                .disabled(store.selectedDocument == nil)

                if store.isLoading {
                    Button {
                        store.cancelLoading()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("Parquet Peek", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }
                Task { @MainActor in
                    await store.open(url: url)
                }
            }
        }
        return accepted
    }
}
