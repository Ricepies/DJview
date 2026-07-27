import Foundation
import SwiftUI
import AppKit
import Combine
import PDFKit
import CDjVuBridge

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

public enum PageTurnDirection {
    case forwardHorizontal
    case backwardHorizontal
    case forwardVertical
    case backwardVertical
}

public enum ExportDocumentFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF Document (.pdf)"
    case epub = "EPUB E-Book (.epub)"
    case cbz = "CBZ Comic Archive (.cbz)"
    case tiff = "TIFF Multi-Page Image (.tiff)"
    case pngFolder = "PNG Image Series Folder"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .epub: return "epub"
        case .cbz: return "cbz"
        case .tiff: return "tiff"
        case .pngFolder: return "folder"
        }
    }

    public var icon: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .epub: return "book.closed"
        case .cbz: return "archivebox"
        case .tiff: return "photo.on.rectangle"
        case .pngFolder: return "folder.badge.gearshape"
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
    @Published public var pageTurnDirection: PageTurnDirection = .forwardHorizontal
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

    // Document Batch Export & PDF2DjVu Background Conversion State
    @Published public var isExportModalPresented: Bool = false
    @Published public var isExporting: Bool = false
    @Published public var isPDFConverting: Bool = false
    @Published public var isPDFConversionMinimized: Bool = false
    @Published public var exportProgress: Double = 0.0
    @Published public var exportStatusText: String = ""
    @Published public var isConversionCancelled: Bool = false

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
        self.pageTurnDirection = .forwardHorizontal
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

    public func goToPage(_ pageIndex: Int, animated: Bool = true, vertical: Bool = false) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        if pageIndex > currentPageIndex {
            pageTurnDirection = vertical ? .forwardVertical : .forwardHorizontal
        } else if pageIndex < currentPageIndex {
            pageTurnDirection = vertical ? .backwardVertical : .backwardHorizontal
        }
        currentPageIndex = pageIndex
        isDirectJump = !animated
        targetJumpPageIndex = pageIndex
        loadTextLayer(pageIndex: pageIndex)
        saveReadingPosition()
    }

    public func setCurrentPageFromScroll(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages && pageIndex != currentPageIndex else { return }
        if pageIndex > currentPageIndex {
            pageTurnDirection = .forwardVertical
        } else if pageIndex < currentPageIndex {
            pageTurnDirection = .backwardVertical
        }
        currentPageIndex = pageIndex
        loadTextLayer(pageIndex: pageIndex)
        saveReadingPosition()
    }

    public func nextPage(vertical: Bool = false) {
        let step = (layoutMode == .manga) ? 2 : 1
        pageTurnDirection = vertical ? .forwardVertical : .forwardHorizontal
        goToPage(min(totalPages - 1, currentPageIndex + step), animated: true, vertical: vertical)
    }

    public func previousPage(vertical: Bool = false) {
        let step = (layoutMode == .manga) ? 2 : 1
        pageTurnDirection = vertical ? .backwardVertical : .backwardHorizontal
        goToPage(max(0, currentPageIndex - step), animated: true, vertical: vertical)
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

    // MARK: - Streaming PDF2DjVu Conversion Engine (pdfimages + djvu-rs Lossless Manga Encoder)
    public func convertPDFToDjVu(pdfURL: URL, targetURL: URL, qualityMode: UInt32 = 0) {
        guard FileManager.default.fileExists(atPath: pdfURL.path) else { return }

        isPDFConverting = true
        isPDFConversionMinimized = false
        isConversionCancelled = false
        exportProgress = 0.05
        exportStatusText = "Attempting zero-copy pdfimages extraction..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let pdfPathCStr = pdfURL.path.cString(using: .utf8),
                  let targetPathCStr = targetURL.path.cString(using: .utf8) else {
                DispatchQueue.main.async {
                    self.isPDFConverting = false
                    self.exportStatusText = "Invalid file paths."
                }
                return
            }

            // 1. Try zero-copy pdfimages raw stream extraction first
            let res = djvu_convert_pdf_via_pdfimages(pdfPathCStr, targetPathCStr, qualityMode, 300)

            if res == 0 {
                DispatchQueue.main.async {
                    self.exportProgress = 1.0
                    self.isPDFConverting = false
                    self.openDocument(at: targetURL)
                }
                return
            }

            // 2. If pdfimages is not installed or returned -100, fallback to bounded 1-page disk stream rendering
            DispatchQueue.main.async {
                self.exportStatusText = "Extracting pages sequentially to disk..."
            }

            guard let pdfDoc = PDFDocument(url: pdfURL), pdfDoc.pageCount > 0 else {
                DispatchQueue.main.async {
                    self.isPDFConverting = false
                    self.exportStatusText = "Failed to load PDF."
                }
                return
            }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf_ext_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let total = pdfDoc.pageCount
            for idx in 0..<total {
                if self.isConversionCancelled {
                    DispatchQueue.main.async {
                        self.isPDFConverting = false
                        self.exportStatusText = "Conversion cancelled."
                    }
                    return
                }

                let pct = Double(idx + 1) / Double(total)
                DispatchQueue.main.async {
                    self.exportProgress = pct * 0.7
                    self.exportStatusText = "Streaming page \(idx + 1) of \(total) to disk..."
                }

                autoreleasepool {
                    if let page = pdfDoc.page(at: idx),
                       let pngData = self.renderPDFPageToPNGData(page: page, scale: 1.5) {
                        let pageFile = tempDir.appendingPathComponent(String(format: "page_%05d.png", idx + 1))
                        try? pngData.write(to: pageFile)
                    }
                }
            }

            DispatchQueue.main.async {
                self.exportProgress = 0.8
                self.exportStatusText = "Encoding DjVu bundle with djvu-rs shared symbol dictionary..."
            }

            guard let tempDirCStr = tempDir.path.cString(using: .utf8) else { return }
            let dirRes = djvu_convert_dir_to_djvu(tempDirCStr, targetPathCStr, qualityMode, 300)

            DispatchQueue.main.async {
                self.exportProgress = 1.0
                self.isPDFConverting = false
                if dirRes == 0 {
                    self.openDocument(at: targetURL)
                } else {
                    self.exportStatusText = "Error encoding DjVu bundle: \(dirRes)"
                }
            }
        }
    }

    private func renderPDFPageToPNGData(page: PDFPage, scale: CGFloat = 1.5) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let maxDim: CGFloat = 2048.0
        let currentMax = max(bounds.width, bounds.height)
        let fitScale = min(scale, maxDim / max(1.0, currentMax))

        let w = Int(bounds.width * fitScale)
        let h = Int(bounds.height * fitScale)

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: fitScale, y: fitScale)
            page.draw(with: .mediaBox, to: ctx)
        }
        img.unlockFocus()

        guard let tiffData = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData
    }

    public func cancelPDFConversion() {
        isConversionCancelled = true
    }

    public func togglePDFConversionMinimized() {
        isPDFConversionMinimized.toggle()
    }

    // MARK: - High-Fidelity Cocoa PNG / JPEG Single Page Export
    public func exportCurrentPage(format: Int, targetURL: URL) -> Bool {
        guard let engine = engine else { return false }
        let dim = engine.getPageDimension(pageIndex: currentPageIndex) ?? (600, 800, 72)
        let dw = dim.width
        let dh = dim.height

        let byteCount = dw * dh * 4
        var buffer = [UInt8](repeating: 0, count: byteCount)

        let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            var aw: UInt32 = 0
            var ah: UInt32 = 0
            return djvu_doc_render_page_rgba(engine.docPtr, UInt32(currentPageIndex), UInt32(dw), UInt32(dh), UInt32(layerMode.rawValue), base, &aw, &ah)
        }

        if res == 0 {
            let data = Data(buffer)
            if let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: dw,
                pixelsHigh: dh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: dw * 4,
                bitsPerPixel: 32
            ) {
                data.withUnsafeBytes { rawBuffer in
                    if let base = rawBuffer.baseAddress, let bitmapData = rep.bitmapData {
                        memcpy(bitmapData, base, byteCount)
                    }
                }

                let fileType: NSBitmapImageRep.FileType = (format == 0) ? .png : .jpeg
                let props: [NSBitmapImageRep.PropertyKey: Any] = (format == 1) ? [.compressionFactor: 0.9] : [:]

                if let outputData = rep.representation(using: fileType, properties: props) {
                    do {
                        try outputData.write(to: targetURL, options: .atomic)
                        print("Successfully exported page \(currentPageIndex + 1) to \(targetURL.path) (\(outputData.count) bytes)")
                        return true
                    } catch {
                        print("Error writing exported image to \(targetURL.path): \(error)")
                    }
                }
            }
        }

        return engine.exportPage(pageIndex: currentPageIndex, format: format, outputPath: targetURL.path)
    }

    // MARK: - Batch Document Conversion System (DjVu -> PDF, EPUB, CBZ, TIFF, PNG Series)
    public func convertDocumentBatch(
        format: ExportDocumentFormat,
        startPage: Int,
        endPage: Int,
        qualityScale: Double,
        targetURL: URL
    ) {
        guard let engine = engine else { return }
        let total = max(1, endPage - startPage + 1)

        isExporting = true
        exportProgress = 0.0
        exportStatusText = "Preparing conversion for \(format.rawValue)..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            switch format {
            case .pdf:
                self.performPDFConversion(engine: engine, startPage: startPage, endPage: endPage, scale: qualityScale, targetURL: targetURL, total: total)

            case .cbz:
                self.performCBZConversion(engine: engine, startPage: startPage, endPage: endPage, scale: qualityScale, targetURL: targetURL, total: total)

            case .epub:
                self.performEPUBConversion(engine: engine, startPage: startPage, endPage: endPage, scale: qualityScale, targetURL: targetURL, total: total)

            case .tiff:
                self.performTIFFConversion(engine: engine, startPage: startPage, endPage: endPage, scale: qualityScale, targetURL: targetURL, total: total)

            case .pngFolder:
                self.performPNGFolderConversion(engine: engine, startPage: startPage, endPage: endPage, scale: qualityScale, targetURL: targetURL, total: total)
            }
        }
    }

    private func performPDFConversion(engine: DjVuEngine, startPage: Int, endPage: Int, scale: Double, targetURL: URL, total: Int) {
        let pdfDoc = PDFDocument()

        for (idx, pIdx) in (startPage...endPage).enumerated() {
            let currentPct = Double(idx + 1) / Double(total)
            DispatchQueue.main.async {
                self.exportProgress = currentPct
                self.exportStatusText = "Converting Page \(pIdx + 1) of \(endPage + 1) to PDF..."
            }

            if let img = renderPageToNSImage(engine: engine, pageIndex: pIdx, scale: scale),
               let pdfPage = PDFPage(image: img) {
                pdfDoc.insert(pdfPage, at: pdfDoc.pageCount)
            }
        }

        DispatchQueue.main.async {
            self.exportStatusText = "Finalizing PDF File..."
        }

        let success = pdfDoc.write(to: targetURL)

        DispatchQueue.main.async {
            self.isExporting = false
            self.isExportModalPresented = false
            if success {
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            }
        }
    }

    private func performCBZConversion(engine: DjVuEngine, startPage: Int, endPage: Int, scale: Double, targetURL: URL, total: Int) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for (idx, pIdx) in (startPage...endPage).enumerated() {
            let currentPct = Double(idx + 1) / Double(total)
            DispatchQueue.main.async {
                self.exportProgress = currentPct
                self.exportStatusText = "Processing Page \(pIdx + 1) of \(endPage + 1) for CBZ Archive..."
            }

            if let imgData = renderPageToImageData(engine: engine, pageIndex: pIdx, scale: scale, format: .jpeg) {
                let fileName = String(format: "%04d.jpg", idx + 1)
                let filePath = tempDir.appendingPathComponent(fileName)
                try? imgData.write(to: filePath)
            }
        }

        DispatchQueue.main.async {
            self.exportStatusText = "Compressing CBZ Archive..."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        process.arguments = ["-r", targetURL.path, "."]

        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: tempDir)

        DispatchQueue.main.async {
            self.isExporting = false
            self.isExportModalPresented = false
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func performEPUBConversion(engine: DjVuEngine, startPage: Int, endPage: Int, scale: Double, targetURL: URL, total: Int) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("epub_\(UUID().uuidString)")
        let metaInf = tempDir.appendingPathComponent("META-INF")
        let ops = tempDir.appendingPathComponent("OPS")
        let imagesDir = ops.appendingPathComponent("images")

        try? FileManager.default.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        // mimetype
        try? "application/epub+zip".write(to: tempDir.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)

        // container.xml
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try? containerXML.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        var manifestItems: [String] = []
        var spineItems: [String] = []

        for (idx, pIdx) in (startPage...endPage).enumerated() {
            let currentPct = Double(idx + 1) / Double(total)
            DispatchQueue.main.async {
                self.exportProgress = currentPct
                self.exportStatusText = "Formatting Page \(pIdx + 1) of \(endPage + 1) for EPUB..."
            }

            let imgName = String(format: "page_%04d.jpg", idx + 1)
            let imgURL = imagesDir.appendingPathComponent(imgName)
            if let imgData = renderPageToImageData(engine: engine, pageIndex: pIdx, scale: scale, format: .jpeg) {
                try? imgData.write(to: imgURL)
            }

            let pageId = String(format: "page_%04d", idx + 1)
            let xhtmlName = "\(pageId).xhtml"

            let textZones = engine.getTextZones(pageIndex: pIdx)
            let extractedText = extractText(from: textZones)

            let xhtmlContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head><title>Page \(pIdx + 1)</title></head>
            <body>
              <div><img src="images/\(imgName)" alt="Page \(pIdx + 1)" style="max-width:100%;"/></div>
              <div class="ocr-text">\(extractedText)</div>
            </body>
            </html>
            """
            try? xhtmlContent.write(to: ops.appendingPathComponent(xhtmlName), atomically: true, encoding: String.Encoding.utf8)

            manifestItems.append("<item id=\"\(pageId)\" href=\"\(xhtmlName)\" media-type=\"application/xhtml+xml\"/>")
            manifestItems.append("<item id=\"img_\(pageId)\" href=\"images/\(imgName)\" media-type=\"image/jpeg\"/>")
            spineItems.append("<itemref idref=\"\(pageId)\"/>")
        }

        // package.opf
        let docTitle = documentURL?.deletingPathExtension().lastPathComponent ?? "DjVu Document"
        let opfContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(docTitle)</dc:title>
            <dc:language>en</dc:language>
            <dc:identifier id="BookId">urn:uuid:\(UUID().uuidString)</dc:identifier>
          </metadata>
          <manifest>
            \(manifestItems.joined(separator: "\n    "))
          </manifest>
          <spine>
            \(spineItems.joined(separator: "\n    "))
          </spine>
        </package>
        """
        try? opfContent.write(to: ops.appendingPathComponent(opfContent), atomically: true, encoding: .utf8)

        DispatchQueue.main.async {
            self.exportStatusText = "Assembling EPUB Package..."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        process.arguments = ["-X0", targetURL.path, "mimetype"]
        try? process.run()
        process.waitUntilExit()

        let process2 = Process()
        process2.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process2.currentDirectoryURL = tempDir
        process2.arguments = ["-rg", targetURL.path, "META-INF", "OPS"]
        try? process2.run()
        process2.waitUntilExit()

        try? FileManager.default.removeItem(at: tempDir)

        DispatchQueue.main.async {
            self.isExporting = false
            self.isExportModalPresented = false
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func performTIFFConversion(engine: DjVuEngine, startPage: Int, endPage: Int, scale: Double, targetURL: URL, total: Int) {
        var reps: [NSImageRep] = []

        for (idx, pIdx) in (startPage...endPage).enumerated() {
            let currentPct = Double(idx + 1) / Double(total)
            DispatchQueue.main.async {
                self.exportProgress = currentPct
                self.exportStatusText = "Rendering Page \(pIdx + 1) of \(endPage + 1) for TIFF..."
            }

            let (dw, dh, _) = engine.getPageDimension(pageIndex: pIdx) ?? (600, 800, 72)
            let w = Int(Double(dw) * scale)
            let h = Int(Double(dh) * scale)
            let byteCount = w * h * 4
            var buffer = [UInt8](repeating: 0, count: byteCount)

            let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return -1 }
                var aw: UInt32 = 0
                var ah: UInt32 = 0
                return djvu_doc_render_page_rgba(engine.docPtr, UInt32(pIdx), UInt32(w), UInt32(h), UInt32(self.layerMode.rawValue), base, &aw, &ah)
            }

            if res == 0 {
                let data = Data(buffer)
                if let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: w,
                    pixelsHigh: h,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .calibratedRGB,
                    bytesPerRow: w * 4,
                    bitsPerPixel: 32
                ) {
                    data.withUnsafeBytes { rawBuffer in
                        if let base = rawBuffer.baseAddress, let bitmapData = rep.bitmapData {
                            memcpy(bitmapData, base, byteCount)
                        }
                    }
                    reps.append(rep)
                }
            }
        }

        DispatchQueue.main.async {
            self.exportStatusText = "Encoding Multi-Page TIFF Image..."
        }

        if let tiffData = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0.9) {
            try? tiffData.write(to: targetURL)
        }

        DispatchQueue.main.async {
            self.isExporting = false
            self.isExportModalPresented = false
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func performPNGFolderConversion(engine: DjVuEngine, startPage: Int, endPage: Int, scale: Double, targetURL: URL, total: Int) {
        try? FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

        for (idx, pIdx) in (startPage...endPage).enumerated() {
            let currentPct = Double(idx + 1) / Double(total)
            DispatchQueue.main.async {
                self.exportProgress = currentPct
                self.exportStatusText = "Exporting PNG Page \(pIdx + 1) of \(endPage + 1)..."
            }

            let fileName = String(format: "Page_%04d.png", pIdx + 1)
            let pageURL = targetURL.appendingPathComponent(fileName)

            if let imgData = renderPageToImageData(engine: engine, pageIndex: pIdx, scale: scale, format: .png) {
                try? imgData.write(to: pageURL)
            }
        }

        DispatchQueue.main.async {
            self.isExporting = false
            self.isExportModalPresented = false
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func renderPageToNSImage(engine: DjVuEngine, pageIndex: Int, scale: Double) -> NSImage? {
        let (dw, dh, _) = engine.getPageDimension(pageIndex: pageIndex) ?? (600, 800, 72)
        let w = Int(Double(dw) * scale)
        let h = Int(Double(dh) * scale)
        let byteCount = w * h * 4
        var buffer = [UInt8](repeating: 0, count: byteCount)

        var aw: UInt32 = 0
        var ah: UInt32 = 0
        let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return djvu_doc_render_page_rgba(engine.docPtr, UInt32(pageIndex), UInt32(w), UInt32(h), UInt32(layerMode.rawValue), base, &aw, &ah)
        }
        guard res == 0 else { return nil }

        let data = Data(buffer)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)

        guard let cgImage = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }

    private func renderPageToImageData(engine: DjVuEngine, pageIndex: Int, scale: Double, format: NSBitmapImageRep.FileType) -> Data? {
        let (dw, dh, _) = engine.getPageDimension(pageIndex: pageIndex) ?? (600, 800, 72)
        let w = Int(Double(dw) * scale)
        let h = Int(Double(dh) * scale)
        let byteCount = w * h * 4
        var buffer = [UInt8](repeating: 0, count: byteCount)

        var aw: UInt32 = 0
        var ah: UInt32 = 0
        let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return djvu_doc_render_page_rgba(engine.docPtr, UInt32(pageIndex), UInt32(w), UInt32(h), UInt32(layerMode.rawValue), base, &aw, &ah)
        }
        guard res == 0 else { return nil }

        let data = Data(buffer)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: w * 4,
            bitsPerPixel: 32
        ) else { return nil }

        data.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress, let bitmapData = rep.bitmapData {
                memcpy(bitmapData, base, byteCount)
            }
        }

        let props: [NSBitmapImageRep.PropertyKey: Any] = (format == .jpeg) ? [.compressionFactor: 0.9] : [:]
        return rep.representation(using: format, properties: props)
    }

    private func extractText(from zones: [TextZone]) -> String {
        var text = ""
        for zone in zones {
            if !zone.text.isEmpty {
                text += zone.text + " "
            }
            if !zone.children.isEmpty {
                text += extractText(from: zone.children)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Recently Opened System & Deterministic Per-File Complete Settings Memory
    public func clearRecentFiles() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }

    private func fileKey(for url: URL, prefix: String) -> String {
        let pathData = Data(url.path.utf8)
        let base64 = pathData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(prefix)_\(base64)"
    }

    public func saveReadingPosition() {
        guard !isRestoringState, let url = documentURL else { return }
        let key = fileKey(for: url, prefix: "pos")
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
        let key = fileKey(for: url, prefix: "pos")
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
        let key = fileKey(for: url, prefix: "ubm")
        if let data = try? JSONEncoder().encode(userBookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadUserBookmarks(for url: URL) {
        let key = fileKey(for: url, prefix: "ubm")
        if let data = UserDefaults.standard.data(forKey: key),
           let bms = try? JSONDecoder().decode([UserBookmark].self, from: data) {
            self.userBookmarks = bms
        }
    }

    private func savePageNotesState() {
        guard let url = documentURL else { return }
        let key = fileKey(for: url, prefix: "pnotes")
        if let data = try? JSONEncoder().encode(pageNotes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadPageNotes(for url: URL) {
        let key = fileKey(for: url, prefix: "pnotes")
        if let data = UserDefaults.standard.data(forKey: key),
           let notes = try? JSONDecoder().decode([PageNote].self, from: data) {
            self.pageNotes = notes
        }
    }

    private func loadAnnotations(for url: URL) {
        let key = fileKey(for: url, prefix: "ann")
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Annotation].self, from: data) {
            self.annotations = list
        }
    }

    public func saveAnnotationsState() {
        guard let url = documentURL else { return }
        let key = fileKey(for: url, prefix: "ann")
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
