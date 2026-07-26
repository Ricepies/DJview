import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct MainView: View {
    @StateObject var viewModel = AppViewModel()
    @State private var isTargetedForDrop = false

    public var body: some View {
        NavigationSplitView {
            if viewModel.isSidebarVisible {
                SidebarView(viewModel: viewModel)
            }
        } detail: {
            ZStack {
                if viewModel.engine != nil {
                    switch viewModel.layoutMode {
                    case .continuous:
                        ContinuousScrollView(viewModel: viewModel)
                    case .singlePage:
                        SinglePageCanvasView(viewModel: viewModel)
                    case .manga:
                        MangaPageView(viewModel: viewModel)
                    }
                } else {
                    EmptyStateView {
                        selectAndOpenDocument()
                    }
                }
            }
            .toolbar {
                CustomToolbar(viewModel: viewModel, onOpenDocument: selectAndOpenDocument)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.pathExtension.lowercased() == "djvu" || url.pathExtension.lowercased() == "djv" {
                    DispatchQueue.main.async {
                        viewModel.openDocument(at: url)
                    }
                }
            }
            return true
        }
        .background(
            Button(action: {
                viewModel.activateSearch()
            }) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
        )
    }

    private func selectAndOpenDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "djvu") ?? .data,
            UTType(filenameExtension: "djv") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.openDocument(at: url)
        }
    }
}

struct EmptyStateView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)
                .symbolEffect(.bounce, value: true)

            VStack(spacing: 6) {
                Text("DJView Reader")
                    .font(.title)
                    .bold()
                Text("High-performance native macOS DjVu viewer with Metal acceleration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(action: onOpen) {
                Label("Open DjVu File...", systemImage: "arrow.up.doc.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Or drag and drop a .djvu file anywhere")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }
}

struct CustomToolbar: ToolbarContent {
    @ObservedObject var viewModel: AppViewModel
    let onOpenDocument: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: { viewModel.isSidebarVisible.toggle() }) {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")

            Button(action: onOpenDocument) {
                Image(systemName: "folder")
            }
            .help("Open DjVu File")
        }

        ToolbarItemGroup(placement: .principal) {
            if viewModel.totalPages > 0 {
                HStack(spacing: 8) {
                    Button(action: { viewModel.previousPage() }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentPageIndex <= 0)

                    Text("\(viewModel.currentPageIndex + 1) / \(viewModel.totalPages)")
                        .font(.body)
                        .monospacedDigit()

                    Button(action: { viewModel.nextPage() }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentPageIndex >= viewModel.totalPages - 1)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.engine != nil {
                // Search Trigger Button
                Button(action: { viewModel.activateSearch() }) {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search Document (Cmd+F)")

                // Zoom Controls
                HStack(spacing: 4) {
                    Button(action: { viewModel.zoomOut() }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(viewModel.zoomScale * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                    Button(action: { viewModel.zoomIn() }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }

                // Layout Mode Picker
                Menu {
                    ForEach(ViewLayoutMode.allCases) { mode in
                        Button(action: { viewModel.layoutMode = mode }) {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: viewModel.layoutMode.icon)
                }
                .help("Layout Mode")

                // Layer Mode Picker
                Menu {
                    ForEach(LayerMode.allCases) { layer in
                        Button(action: { viewModel.layerMode = layer }) {
                            Label(layer.title, systemImage: layer.icon)
                        }
                    }
                } label: {
                    Image(systemName: viewModel.layerMode.icon)
                }
                .help("DjVu Layer Mode")

                // Metal Shader Color Mode Picker
                Menu {
                    ForEach(ColorShaderMode.allCases) { mode in
                        Button(action: { viewModel.shaderMode = mode }) {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: viewModel.shaderMode.icon)
                }
                .help("Color Filter Mode")

                // Bookmark Toggle Button
                Button(action: { viewModel.toggleBookmarkCurrentPage() }) {
                    Image(systemName: viewModel.userBookmarks.contains(viewModel.currentPageIndex) ? "bookmark.fill" : "bookmark")
                        .foregroundColor(viewModel.userBookmarks.contains(viewModel.currentPageIndex) ? .red : .primary)
                }
                .help("Bookmark Current Page")

                // Export Page Button
                Menu {
                    Button("Export Page as PNG...") {
                        exportPage(format: 0)
                    }
                    Button("Export Page as JPEG...") {
                        exportPage(format: 1)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export Page")
            }
        }
    }

    private func exportPage(format: Int) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format == 0 ? .png : .jpeg]
        savePanel.nameFieldStringValue = "Page_\(viewModel.currentPageIndex + 1).\(format == 0 ? "png" : "jpg")"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            _ = viewModel.exportCurrentPage(format: format, targetURL: url)
        }
    }
}
