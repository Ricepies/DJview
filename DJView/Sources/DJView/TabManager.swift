import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tab Model
public final class DocumentTab: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public var viewModel: AppViewModel
    @Published public var title: String

    public init(viewModel: AppViewModel = AppViewModel(), title: String = "New Tab") {
        self.viewModel = viewModel
        self.title = title
    }
}

// MARK: - Tab Manager
public final class TabManager: ObservableObject {
    @Published public var tabs: [DocumentTab] = [DocumentTab()]
    @Published public var activeTabID: UUID

    public init() {
        let first = DocumentTab()
        tabs = [first]
        activeTabID = first.id
    }

    public var activeTab: DocumentTab? {
        tabs.first { $0.id == activeTabID }
    }

    public func newTab(openingURL url: URL? = nil) {
        let tab = DocumentTab()
        tabs.append(tab)
        activeTabID = tab.id
        if let url = url {
            tab.viewModel.openDocument(at: url)
            tab.title = url.deletingPathExtension().lastPathComponent
        }
    }

    public func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs.remove(at: idx)
            // Move active to adjacent tab
            if activeTabID == id {
                let newIdx = max(0, min(idx, tabs.count - 1))
                activeTabID = tabs[newIdx].id
            }
        }
    }

    public func activateNext() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activeTabID = tabs[(idx + 1) % tabs.count].id
    }

    public func activatePrevious() {
        guard let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activeTabID = tabs[(idx - 1 + tabs.count) % tabs.count].id
    }

    public func updateTitle(for tab: DocumentTab) {
        if let url = tab.viewModel.documentURL {
            tab.title = url.deletingPathExtension().lastPathComponent
        } else {
            tab.title = "New Tab"
        }
    }
}
