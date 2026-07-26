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

public final class AppViewModel: ObservableObject {
    @Published public var engine: DjVuEngine?
    @Published public var documentURL: URL?
    @Published public var currentPageIndex: Int = 0
    @Published public var targetJumpPageIndex: Int? = nil
    @Published public var isDirectJump: Bool = false
    @Published public var totalPages: Int = 0
    @Published public var zoomScale: Double = 1.0
    @Published public var zoomMode: ZoomMode = .fitWidth
    @Published public var layoutMode: ViewLayoutMode = .continuous
    @Published public var layerMode: LayerMode = .composite
    @Published public var shaderMode: ColorShaderMode = .normal
    @Published public var selectedSidebarTab: SidebarTab = .thumbnails
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

    // Annotations & Sticky Notes
    @Published public var annotations: [Annotation] = []

    // Text selection & copy
    @Published public var currentTextZones: [TextZone] = []
    @Published public var selectedText: String = ""

    // Recent Files & Memory
    @Published public var recentFiles: [URL] = []

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSearchDebounce()
        loadRecentFiles()
    }

    public func openDocument(at url: URL) {
        guard let engine = DjVuEngine(filePath: url.path) else {
            print("Failed to open DjVu document at: \(url.path)")
            return
        }

        self.engine = engine
        self.documentURL = url
        self.totalPages = engine.pageCount
        self.currentPageIndex = 0
        self.isDirectJump = true
        self.targetJumpPageIndex = 0

        self.bookmarks = engine.getBookmarks()
        loadReadingPosition(for: url)
        loadUserBookmarks(for: url)
        loadTextLayer(pageIndex: currentPageIndex)
        loadAnnotations(for: url)
        addToRecentFiles(url: url)
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
        // Minimum zoom 0.1% (0.001) for tiny windows up to 500% (5.0)
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
    }

    public func deleteBookmark(_ bookmark: UserBookmark) {
        userBookmarks.removeAll(where: { $0.id == bookmark.id })
        saveBookmarksState()
    }

    // MARK: - Notes & Annotations System
    public func addStickyNote(pageIndex: Int, noteText: String, colorHex: String = "#FFEB3B", rect: CGRect = CGRect(x: 40, y: 40, width: 180, height: 120)) {
        let ann = Annotation(
            pageIndex: pageIndex,
            kind: .note,
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height,
            colorHex: colorHex,
            noteText: noteText
        )
        annotations.append(ann)
        saveAnnotationsState()
    }

    public func updateAnnotationNoteText(id: UUID, newText: String) {
        if let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].noteText = newText
            saveAnnotationsState()
        }
    }

    public func deleteAnnotation(_ annotation: Annotation) {
        annotations.removeAll(where: { $0.id == annotation.id })
        saveAnnotationsState()
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

    // MARK: - Persistence & Memory
    private func saveReadingPosition() {
        guard let url = documentURL else { return }
        let key = "pos_" + url.path.hashValue.description
        let pos = DocumentPosition(
            pageIndex: currentPageIndex,
            scrollOffsetY: 0.0,
            zoomScale: zoomScale,
            layoutMode: layoutMode.rawValue
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

    private func loadAnnotations(for url: URL) {
        let key = "ann_" + url.path.hashValue.description
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Annotation].self, from: data) {
            self.annotations = list
        }
    }

    private func saveAnnotationsState() {
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
            recentFiles = paths.map { URL(fileURLWithPath: $0) }
        }
    }
}
