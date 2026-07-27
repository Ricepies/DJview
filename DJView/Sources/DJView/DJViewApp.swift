import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct DejaApp: App {
    @StateObject private var tabManager = TabManager()

    var body: some Scene {
        WindowGroup {
            TabbedDocumentView(tabManager: tabManager)
                .onOpenURL { url in
                    let ext = url.pathExtension.lowercased()
                    guard ext == "djvu" || ext == "djv" else { return }
                    openURL(url)
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    openWithPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Tab") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        tabManager.newTab()
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Close Tab") {
                    if let id = tabManager.activeTab?.id {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabManager.closeTab(id: id)
                        }
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
    }

    private func openWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open DjVu Document"
        panel.message = "Choose a DjVu file (.djvu, .djv) to read"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "djvu") ?? .data,
            UTType(filenameExtension: "djv") ?? .data
        ]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                openURL(url)
            }
        }
    }

    private func openURL(_ url: URL) {
        if let active = tabManager.activeTab, active.viewModel.engine == nil {
            active.viewModel.openDocument(at: url)
            tabManager.updateTitle(for: active)
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                tabManager.newTab(openingURL: url)
            }
        }
    }
}
