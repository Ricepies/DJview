import Foundation
import SwiftUI
import AppKit
import Combine

public enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails = "Thumbnails"
    case toc = "Table of Contents"
    case search = "Search"
    case annotations = "Annotations"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .thumbnails: return "square.grid.2x2"
        case .toc: return "list.bullet.indent"
        case .search: return "magnifyingglass"
        case .annotations: return "highlighter"
        }
    }
}

public final class AppViewModel: ObservableObject {
    @Published public var engine: DjVuEngine?
    @Published public var documentURL: URL?
    @Published public var currentPageIndex: Int = 0
    @Published public var totalPages: Int = 0
    @Published public var zoomScale: Double = 1.0
    @Published public var zoomMode: ZoomMode = .fitWidth
    @Published public var layoutMode: ViewLayoutMode = .continuous
    @Published public var layerMode: LayerMode = .composite
    @Published public var shaderMode: ColorShaderMode = .normal
    @Published public var selectedSidebarTab: SidebarTab = .thumbnails
    @Published public var isSidebarVisible: Bool = true
    @Published public var useMetalRenderer: Bool = true

    // Bookmarks & TOC
    @Published public var bookmarks: [BookmarkItem] = []
    @Published public var userBookmarks: Set<Int> = []

    // Search
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [SearchResult] = []
    @Published public var isSearching: Bool = false
    @Published public var currentMatchIndex: Int = 0
    @Published public var shouldFocusSearchField: Bool = false

    // Annotations
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

        self.bookmarks = engine.getBookmarks()
        loadReadingPosition(for: url)
        loadTextLayer(pageIndex: currentPageIndex)
        loadAnnotations(for: url)
        addToRecentFiles(url: url)
    }

    public func goToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        currentPageIndex = pageIndex
        loadTextLayer(pageIndex: pageIndex)
        saveReadingPosition()
    }

    public func nextPage() {
        if layoutMode == .manga {
            goToPage(min(totalPages - 1, currentPageIndex + 2))
        } else {
            goToPage(min(totalPages - 1, currentPageIndex + 1))
        }
    }

    public func previousPage() {
        if layoutMode == .manga {
            goToPage(max(0, currentPageIndex - 2))
        } else {
            goToPage(max(0, currentPageIndex - 1))
        }
    }

    public func setZoomScale(_ scale: Double) {
        zoomScale = max(0.2, min(5.0, scale))
        zoomMode = .custom(zoomScale)
        saveReadingPosition()
    }

    public func zoomIn() {
        setZoomScale(zoomScale + 0.15)
    }

    public func zoomOut() {
        setZoomScale(zoomScale - 0.15)
    }

    // MARK: - Search Activation & Navigation (Cmd+F)
    public func activateSearch() {
        isSidebarVisible = true
        selectedSidebarTab = .search
        shouldFocusSearchField = true
    }

    public func nextSearchMatch() {
        guard !searchResults.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchResults.count
        let match = searchResults[currentMatchIndex]
        goToPage(match.page)
    }

    public func previousSearchMatch() {
        guard !searchResults.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchResults.count) % searchResults.count
        let match = searchResults[currentMatchIndex]
        goToPage(match.page)
    }

    public func toggleBookmarkCurrentPage() {
        if userBookmarks.contains(currentPageIndex) {
            userBookmarks.remove(currentPageIndex)
        } else {
            userBookmarks.insert(currentPageIndex)
        }
        saveBookmarksState()
    }

    public func addAnnotation(kind: AnnotationKind, rect: CGRect, colorHex: String = "#FFEB3B", noteText: String = "") {
        let ann = Annotation(
            pageIndex: currentPageIndex,
            kind: kind,
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let zones = engine.getTextZones(pageIndex: pageIndex)
            DispatchQueue.main.async {
                self?.currentTextZones = zones
            }
        }
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = engine.searchText(query: query)
            DispatchQueue.main.async {
                self?.searchResults = results
                self?.currentMatchIndex = 0
                self?.isSearching = false
                if let firstMatch = results.first {
                    self?.goToPage(firstMatch.page)
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
            self.currentPageIndex = max(0, min(totalPages - 1, pos.pageIndex))
            self.zoomScale = pos.zoomScale
            self.zoomMode = .custom(pos.zoomScale)
            if let layout = ViewLayoutMode(rawValue: pos.layoutMode) {
                self.layoutMode = layout
            }
        }
    }

    private func saveBookmarksState() {
        guard let url = documentURL else { return }
        let key = "bm_" + url.path.hashValue.description
        let arr = Array(userBookmarks)
        UserDefaults.standard.set(arr, forKey: key)
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
