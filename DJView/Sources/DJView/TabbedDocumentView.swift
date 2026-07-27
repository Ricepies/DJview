import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Root tabbed container
struct TabbedDocumentView: View {
    @ObservedObject var tabManager: TabManager

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar sits above the window toolbar area
            TabBarView(tabManager: tabManager, onNewTab: openNewTab)

            // Active tab content
            if let tab = tabManager.activeTab {
                MainView(viewModel: tab.viewModel)
                    .id(tab.id) // force full view recreation on tab switch
                    .onChange(of: tab.viewModel.documentURL) { url in
                        tabManager.updateTitle(for: tab)
                    }
            }
        }
        // Keyboard shortcuts for tab management
        .background(
            ZStack {
                // Cmd+T: new tab
                Button("") { openNewTab() }
                    .keyboardShortcut("t", modifiers: .command)
                // Cmd+W: close active tab
                Button("") {
                    if let id = tabManager.activeTab?.id {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabManager.closeTab(id: id)
                        }
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                // Ctrl+Tab: next tab
                Button("") { tabManager.activateNext() }
                    .keyboardShortcut(.tab, modifiers: .control)
                // Ctrl+Shift+Tab: previous tab
                Button("") { tabManager.activatePrevious() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
            }
            .opacity(0)
        )
    }

    private func openNewTab() {
        withAnimation(.easeInOut(duration: 0.18)) {
            tabManager.newTab()
        }
    }

    // Called from the app-level open panel / onOpenURL
    func openURL(_ url: URL) {
        // If active tab has no document, open in it; else open new tab
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
