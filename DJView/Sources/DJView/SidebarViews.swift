import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // macOS HIG Standard Segmented Sidebar Header
            Picker("Sidebar Section", selection: $viewModel.selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .tag(tab)
                        .help(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch viewModel.selectedSidebarTab {
                case .thumbnails:
                    ThumbnailsView(viewModel: viewModel)
                case .toc:
                    TOCView(viewModel: viewModel)
                case .bookmarks:
                    BookmarksAndNotesView(viewModel: viewModel)
                case .search:
                    SearchSidebarView(viewModel: viewModel)
                }
            }
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 180, idealWidth: 230, maxWidth: 360)
    }
}

// MARK: - Thumbnails View with Apple HIG Layout
struct ThumbnailsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { geo in
            let availableWidth = max(100, geo.size.width - 24)
            let cellWidth = min(availableWidth, max(95, availableWidth / floor(max(1, availableWidth / 115))))
            let cellHeight = cellWidth * 1.32
            let columns = [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth), spacing: 10)]

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                            ThumbnailCell(
                                pageIndex: pageIndex,
                                width: cellWidth,
                                height: cellHeight,
                                isSelected: viewModel.currentPageIndex == pageIndex,
                                isBookmarked: viewModel.isPageBookmarked(pageIndex),
                                engine: viewModel.engine,
                                layerMode: viewModel.layerMode
                            )
                            .id(pageIndex)
                            .onTapGesture {
                                viewModel.goToPage(pageIndex, animated: false)
                            }
                            .contextMenu {
                                Button(viewModel.isPageBookmarked(pageIndex) ? "Remove Bookmark" : "Add Bookmark") {
                                    viewModel.currentPageIndex = pageIndex
                                    viewModel.toggleBookmarkCurrentPage()
                                }
                                Button("Add Note Here...") {
                                    viewModel.addStickyNote(pageIndex: pageIndex, noteText: "Note on page \(pageIndex + 1)")
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

struct ThumbnailCell: View {
    let pageIndex: Int
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let isBookmarked: Bool
    let engine: DjVuEngine?
    let layerMode: LayerMode

    @State private var image: NSImage? = nil

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(ProgressView().scaleEffect(0.6))
                    }
                }
                .frame(width: width, height: height)
                .cornerRadius(6)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.14), radius: isSelected ? 5 : 2, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                )

                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(4)
                        .shadow(radius: 1)
                }
            }

            Text("\(pageIndex + 1)")
                .font(.caption2)
                .bold()
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: layerMode) { _, _ in
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let renderW = Int(width)
        let renderH = Int(height)
        engine?.renderPage(pageIndex: pageIndex, targetWidth: renderW, targetHeight: renderH, layerMode: layerMode) { img in
            self.image = img
        }
    }
}

// MARK: - Table of Contents View
struct TOCView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.bookmarks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No Table of Contents")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.bookmarks, children: \.children) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text(item.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        if let page = item.pageNum {
                            Text("\(page)")
                                .font(.system(size: 10, weight: .regular))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let page = item.pageNum, page >= 1 {
                            viewModel.goToPage(page - 1, animated: false)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Unified Bookmarks & Notes System View (Apple HIG Compliant)
struct BookmarksAndNotesView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Action Header
            HStack {
                Text("Bookmarks & Notes")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    viewModel.toggleBookmarkCurrentPage()
                }) {
                    Label("Bookmark Page", systemImage: viewModel.isPageBookmarked(viewModel.currentPageIndex) ? "bookmark.fill" : "bookmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button(action: {
                    viewModel.addStickyNote(pageIndex: viewModel.currentPageIndex, noteText: "Note on page \(viewModel.currentPageIndex + 1)")
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Add Sticky Note")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            List {
                // Section 1: User Bookmarks
                Section(header: Text("BOOKMARKS (\(viewModel.userBookmarks.count))").font(.caption2).foregroundColor(.secondary)) {
                    if viewModel.userBookmarks.isEmpty {
                        Text("No bookmarks added")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.userBookmarks) { bm in
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                                Text(bm.title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Text("P. \(bm.pageIndex + 1)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.goToPage(bm.pageIndex, animated: false)
                            }
                            .contextMenu {
                                Button("Delete Bookmark", role: .destructive) {
                                    viewModel.deleteBookmark(bm)
                                }
                            }
                        }
                    }
                }

                // Section 2: Sticky Notes & Highlights
                Section(header: Text("STICKY NOTES & HIGHLIGHTS (\(viewModel.annotations.count))").font(.caption2).foregroundColor(.secondary)) {
                    if viewModel.annotations.isEmpty {
                        Text("No notes or highlights added")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.annotations) { ann in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: ann.kind == .highlight ? "highlighter" : "note.text")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                    Text("\(ann.kind.rawValue) (P. \(ann.pageIndex + 1))")
                                        .font(.caption)
                                        .bold()
                                    Spacer()
                                }

                                if editingNoteId == ann.id {
                                    HStack {
                                        TextField("Edit note...", text: $editingNoteText, onCommit: {
                                            viewModel.updateAnnotationNoteText(id: ann.id, newText: editingNoteText)
                                            editingNoteId = nil
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)

                                        Button("Done") {
                                            viewModel.updateAnnotationNoteText(id: ann.id, newText: editingNoteText)
                                            editingNoteId = nil
                                        }
                                        .font(.caption2)
                                    }
                                } else if !ann.noteText.isEmpty {
                                    Text(ann.noteText)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.goToPage(ann.pageIndex, animated: false)
                            }
                            .contextMenu {
                                Button("Edit Note...") {
                                    editingNoteId = ann.id
                                    editingNoteText = ann.noteText
                                }
                                Button("Delete Note", role: .destructive) {
                                    viewModel.deleteAnnotation(ann)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - Search Sidebar View
struct SearchSidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextField("Search document...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isSearchFocused)

                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(6)

            if !viewModel.searchResults.isEmpty {
                HStack {
                    Text("\(viewModel.currentMatchIndex + 1) of \(viewModel.searchResults.count) matches")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { viewModel.previousSearchMatch() }) {
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.searchResults.isEmpty)

                    Button(action: { viewModel.nextSearchMatch() }) {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.searchResults.isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            Divider()

            if viewModel.isSearching {
                ProgressView("Searching OCR...")
                    .font(.caption)
                    .padding()
                Spacer()
            } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No matches found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                List(0..<viewModel.searchResults.count, id: \.self) { idx in
                    let result = viewModel.searchResults[idx]
                    let isSelected = idx == viewModel.currentMatchIndex

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Page \(result.page + 1)")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(isSelected ? .accentColor : .primary)
                            Spacer()
                        }
                        Text(result.text)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .padding(4)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.currentMatchIndex = idx
                        viewModel.goToPage(result.page, animated: false)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}
