import Foundation
import SwiftUI
import AppKit
import Combine

public enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails = "Thumbnails"
    case toc = "Table of Contents"
    case bookmarks = "Bookmarks & Notes"
    case search = "Search"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .thumbnails: return "square.grid.2x2"
        case .toc: return "list.bullet.indent"
        case .bookmarks: return "bookmark.fill"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - Standard DjVu ANTZ Annotation / Metadata Sidecar Structure
public struct DjVuMetadataSidecar: Codable {
    public var version: String
    public var documentName: String
    public var userBookmarks: [UserBookmark]
    public var pageNotes: [PageNote]
    public var annotations: [Annotation]

    public init(version: String = "1.0", documentName: String, userBookmarks: [UserBookmark], pageNotes: [PageNote], annotations: [Annotation]) {
        self.version = version
        self.documentName = documentName
        self.userBookmarks = userBookmarks
        self.pageNotes = pageNotes
        self.annotations = annotations
    }
}

public final class AppViewModel: ObservableObject {
    @Published public var engine: DjVuEngine?
    @Published public var documentURL: URL?
    @Published public var currentPageIndex: Int = 0
    @Published public var targetJumpPageIndex: Int? = nil
    @Published public var isDirectJump: Bool = false
    @Published public var totalPages: Int = 0
    @Published public var zoomScale: Double = 1.0 {
        didSet { saveReadingPosition() }
    }
    @Published public var zoomMode: ZoomMode = .fitWidth
    @Published public var layoutMode: ViewLayoutMode = .continuous {
        didSet { saveReadingPosition() }
    }
    @Published public var layerMode: LayerMode = .composite {
        didSet { saveReadingPosition() }
    }
    @Published public var shaderMode: ColorShaderMode = .normal {
        didSet { saveReadingPosition() }
    }
    @Published public var selectedSidebarTab: SidebarTab = .thumbnails {
        didSet { saveReadingPosition() }
    }
    @Published public var isSidebarVisible: Bool = true
    @Published public var useMetalRenderer: Bool = true

    // NAVM Document Outline & Custom User Bookmarks
    @Published public var bookmarks: [BookmarkItem] = []
    @Published public var userBookmarks: [UserBookmark] = []

    // Search Popup & Sidebar Results
    @Published public var isSearchPopupVisible: Bool = false
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [SearchResult] = []
    @Published public var isSearching: Bool = false
    @Published public var currentMatchIndex: Int = 0
    @Published public var shouldFocusSearchField: Bool = false

    // Page Notes Mode & Storage (Multiple Notes per Page)
    @Published public var isNoteTakingActive: Bool = false
    @Published public var pageNotes: [PageNote] = []
    @Published public var annotations: [Annotation] = []

    // Text selection & copy
    @Published public var currentTextZones: [TextZone] = []
    @Published public var selectedText: String = ""

    // Recently Opened System
    @Published public var recentFiles: [URL] = []

    private var isRestoringState: Bool = false
    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSearchDebounce()
        loadRecentFiles()
    }

    public func openDocument(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let engine = DjVuEngine(filePath: url.path) else {
            print("Failed to open DjVu document at: \(url.path)")
            return
        }

        isRestoringState = true
        self.engine = engine
        self.documentURL = url
        self.totalPages = engine.pageCount
        self.currentPageIndex = 0
        self.isDirectJump = true
        self.targetJumpPageIndex = 0

        self.bookmarks = engine.getBookmarks()
        loadReadingPosition(for: url)
        loadUserBookmarks(for: url)
        loadPageNotes(for: url)
        loadTextLayer(pageIndex: currentPageIndex)
        loadAnnotations(for: url)

        // DjVu Standards: Auto-import .djvu.meta ANTZ sidecar if present
        importDjVuMetadataSidecar(for: url)

        addToRecentFiles(url: url)
        isRestoringState = false
    }

    public func goToPage(_ pageIndex: Int, animated: Bool = true) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        currentPageIndex = pageIndex
        isDirectJump = !animated
        targetJumpPageIndex = pageIndex
        loadTextLayer(pageIndex: pageIndex)
        saveReadingPosition()
    }

    public func setCurrentPageFromScroll(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages && pageIndex != currentPageIndex else { return }
        currentPageIndex = pageIndex
        loadTextLayer(pageIndex: pageIndex)
        saveReadingPosition()
    }

    public func nextPage() {
        let step = (layoutMode == .manga) ? 2 : 1
        goToPage(min(totalPages - 1, currentPageIndex + step), animated: true)
    }

    public func previousPage() {
        let step = (layoutMode == .manga) ? 2 : 1
        goToPage(max(0, currentPageIndex - step), animated: true)
    }

    public func setZoomScale(_ scale: Double) {
        zoomScale = max(0.001, min(5.0, scale))
        zoomMode = .custom(zoomScale)
        saveReadingPosition()
    }

    public func zoomIn() {
        if zoomScale < 0.1 {
            setZoomScale(zoomScale * 1.5)
        } else {
            setZoomScale(zoomScale + 0.15)
        }
    }

    public func zoomOut() {
        if zoomScale <= 0.1 {
            setZoomScale(zoomScale * 0.7)
        } else {
            setZoomScale(zoomScale - 0.15)
        }
    }

    // MARK: - Search Activation & Instant Direct Jump
    public func activateSearch() {
        isSearchPopupVisible = true
        shouldFocusSearchField = true
    }

    public func dismissSearchPopup() {
        isSearchPopupVisible = false
    }

    public func nextSearchMatch() {
        guard !searchResults.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchResults.count
        let match = searchResults[currentMatchIndex]
        goToPage(match.page, animated: false)
    }

    public func previousSearchMatch() {
        guard !searchResults.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchResults.count) % searchResults.count
        let match = searchResults[currentMatchIndex]
        goToPage(match.page, animated: false)
    }

    // MARK: - User Bookmarks System
    public func isPageBookmarked(_ pageIndex: Int) -> Bool {
        userBookmarks.contains(where: { $0.pageIndex == pageIndex })
    }

    public func toggleBookmarkCurrentPage() {
        if let idx = userBookmarks.firstIndex(where: { $0.pageIndex == currentPageIndex }) {
            userBookmarks.remove(at: idx)
        } else {
            let bm = UserBookmark(pageIndex: currentPageIndex, title: "Page \(currentPageIndex + 1)")
            userBookmarks.append(bm)
            userBookmarks.sort(by: { $0.pageIndex < $1.pageIndex })
        }
        saveBookmarksState()
        exportDjVuMetadataSidecar()
    }

    public func addBookmark(pageIndex: Int, title: String) {
        if let idx = userBookmarks.firstIndex(where: { $0.pageIndex == pageIndex }) {
            userBookmarks[idx].title = title
        } else {
            let bm = UserBookmark(pageIndex: pageIndex, title: title)
            userBookmarks.append(bm)
            userBookmarks.sort(by: { $0.pageIndex < $1.pageIndex })
        }
        saveBookmarksState()
        exportDjVuMetadataSidecar()
    }

    public func deleteBookmark(_ bookmark: UserBookmark) {
        userBookmarks.removeAll(where: { $0.id == bookmark.id })
        saveBookmarksState()
        exportDjVuMetadataSidecar()
    }

    // MARK: - Note Taking Activation & Multiple Page Notes Management
    public func toggleNoteTaking() {
        isNoteTakingActive.toggle()
    }

    public func closeNoteTaking() {
        isNoteTakingActive = false
    }

    public func getPageNotes(for pageIndex: Int) -> [PageNote] {
        pageNotes.filter({ $0.pageIndex == pageIndex })
    }

    @discardableResult
    public func createPageNote(pageIndex: Int, title: String = "", content: String = "") -> PageNote {
        let count = getPageNotes(for: pageIndex).count + 1
        let defaultTitle = title.isEmpty ? "Note \(count) (P. \(pageIndex + 1))" : title
        let note = PageNote(pageIndex: pageIndex, title: defaultTitle, content: content)
        pageNotes.append(note)
        savePageNotesState()
        exportDjVuMetadataSidecar()
        return note
    }

    public func updatePageNote(id: UUID, title: String, content: String) {
        if let idx = pageNotes.firstIndex(where: { $0.id == id }) {
            pageNotes[idx].title = title
            pageNotes[idx].content = content
            pageNotes[idx].updatedAt = Date()
            savePageNotesState()
            exportDjVuMetadataSidecar()
        }
    }

    public func deletePageNote(_ note: PageNote) {
        pageNotes.removeAll(where: { $0.id == note.id })
        savePageNotesState()
        exportDjVuMetadataSidecar()
    }

    // MARK: - Standard DjVu ANTZ Sidecar Export/Import (.djvu.meta)
    public func exportDjVuMetadataSidecar() {
        guard let docURL = documentURL else { return }
        let sidecarURL = docURL.appendingPathExtension("meta")
        let sidecar = DjVuMetadataSidecar(
            documentName: docURL.lastPathComponent,
            userBookmarks: userBookmarks,
            pageNotes: pageNotes,
            annotations: annotations
        )
        if let data = try? JSONEncoder().encode(sidecar) {
            try? data.write(to: sidecarURL)
        }
    }

    public func importDjVuMetadataSidecar(for url: URL) {
        let sidecarURL = url.appendingPathExtension("meta")
        guard FileManager.default.fileExists(atPath: sidecarURL.path),
              let data = try? Data(contentsOf: sidecarURL),
              let sidecar = try? JSONDecoder().decode(DjVuMetadataSidecar.self, from: data) else {
            return
        }

        if !sidecar.userBookmarks.isEmpty {
            self.userBookmarks = sidecar.userBookmarks
        }
        if !sidecar.pageNotes.isEmpty {
            self.pageNotes = sidecar.pageNotes
        }
        if !sidecar.annotations.isEmpty {
            self.annotations = sidecar.annotations
        }
    }

    public func copySelectedTextToClipboard() {
        guard !selectedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
    }

    public func exportCurrentPage(format: Int, targetURL: URL) -> Bool {
        guard let engine = engine else { return false }
        return engine.exportPage(pageIndex: currentPageIndex, format: format, outputPath: targetURL.path)
    }

    private func loadTextLayer(pageIndex: Int) {
        guard let engine = engine else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let zones = engine.getTextZones(pageIndex: pageIndex)
            Task { @MainActor in
                self?.currentTextZones = zones
            }
        }
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    private func performSearch(query: String) {
        guard let engine = engine, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            currentMatchIndex = 0
            isSearching = false
            return
        }

        isSearching = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let results = engine.searchText(query: query)
            Task { @MainActor in
                self?.searchResults = results
                self?.currentMatchIndex = 0
                self?.isSearching = false
                if !results.isEmpty {
                    self?.selectedSidebarTab = .search
                    if let firstMatch = results.first {
                        self?.goToPage(firstMatch.page, animated: false)
                    }
                }
            }
        }
    }

    // MARK: - Recently Opened System & Per-File Complete Settings Memory
    public func clearRecentFiles() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }

    public func saveReadingPosition() {
        guard !isRestoringState, let url = documentURL else { return }
        let key = "pos_" + url.path.hashValue.description
        let pos = DocumentPosition(
            pageIndex: currentPageIndex,
            scrollOffsetY: 0.0,
            zoomScale: zoomScale,
            layoutMode: layoutMode.rawValue,
            layerMode: layerMode.rawValue,
            shaderMode: shaderMode.rawValue,
            selectedSidebarTab: selectedSidebarTab.rawValue
        )
        if let data = try? JSONEncoder().encode(pos) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadReadingPosition(for url: URL) {
        let key = "pos_" + url.path.hashValue.description
        if let data = UserDefaults.standard.data(forKey: key),
           let pos = try? JSONDecoder().decode(DocumentPosition.self, from: data) {
            let idx = max(0, min(totalPages - 1, pos.pageIndex))
            self.currentPageIndex = idx
            self.targetJumpPageIndex = idx
            self.isDirectJump = true
            self.zoomScale = pos.zoomScale
            self.zoomMode = .custom(pos.zoomScale)
            if let layout = ViewLayoutMode(rawValue: pos.layoutMode) {
                self.layoutMode = layout
            }
            if let layer = LayerMode(rawValue: pos.layerMode) {
                self.layerMode = layer
            }
            if let shader = ColorShaderMode(rawValue: pos.shaderMode) {
                self.shaderMode = shader
            }
            if let tab = SidebarTab(rawValue: pos.selectedSidebarTab) {
                self.selectedSidebarTab = tab
            }
        }
    }

    private func saveBookmarksState() {
        guard let url = documentURL else { return }
        let key = "ubm_" + url.path.hashValue.description
        if let data = try? JSONEncoder().encode(userBookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadUserBookmarks(for url: URL) {
        let key = "ubm_" + url.path.hashValue.description
        if let data = UserDefaults.standard.data(forKey: key),
           let bms = try? JSONDecoder().decode([UserBookmark].self, from: data) {
            self.userBookmarks = bms
        }
    }

    private func savePageNotesState() {
        guard let url = documentURL else { return }
        let key = "pnotes_" + url.path.hashValue.description
        if let data = try? JSONEncoder().encode(pageNotes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadPageNotes(for url: URL) {
        let key = "pnotes_" + url.path.hashValue.description
        if let data = UserDefaults.standard.data(forKey: key),
           let notes = try? JSONDecoder().decode([PageNote].self, from: data) {
            self.pageNotes = notes
        }
    }

    private func loadAnnotations(for url: URL) {
        let key = "ann_" + url.path.hashValue.description
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Annotation].self, from: data) {
            self.annotations = list
        }
    }

    public func saveAnnotationsState() {
        guard let url = documentURL else { return }
        let key = "ann_" + url.path.hashValue.description
        if let data = try? JSONEncoder().encode(annotations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func addToRecentFiles(url: URL) {
        var recents = recentFiles.filter { $0 != url }
        recents.insert(url, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        recentFiles = recents
        let paths = recents.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "recentFiles")
    }

    private func loadRecentFiles() {
        if let paths = UserDefaults.standard.stringArray(forKey: "recentFiles") {
            recentFiles = paths.compactMap {
                let u = URL(fileURLWithPath: $0)
                return FileManager.default.fileExists(atPath: u.path) ? u : nil
            }
        }
    }
}
