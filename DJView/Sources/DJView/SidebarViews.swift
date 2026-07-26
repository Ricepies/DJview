import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // macOS HIG Standard Segmented Sidebar Header (large icon size)
            Picker("Sidebar Section", selection: $viewModel.selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .font(.system(size: 15))
                        .tag(tab)
                        .help(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
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
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 380)
    }
}

// MARK: - Thumbnails View with Apple HIG Layout & High Visibility
struct ThumbnailsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { geo in
            let availableWidth = max(100, geo.size.width - 24)
            let cellWidth = min(availableWidth, max(105, availableWidth / floor(max(1, availableWidth / 125))))
            let cellHeight = cellWidth * 1.32
            let columns = [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth), spacing: 12)]

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                            ThumbnailCell(
                                pageIndex: pageIndex,
                                width: cellWidth,
                                height: cellHeight,
                                isSelected: viewModel.currentPageIndex == pageIndex,
                                isBookmarked: viewModel.isPageBookmarked(pageIndex),
                                noteCount: viewModel.getPageNotes(for: pageIndex).count,
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
                                Button("Add Note for Page \(pageIndex + 1)...") {
                                    viewModel.currentPageIndex = pageIndex
                                    viewModel.createPageNote(pageIndex: pageIndex)
                                    viewModel.isNoteTakingActive = true
                                }
                            }
                        }
                    }
                    .padding(12)
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
    let noteCount: Int
    let engine: DjVuEngine?
    let layerMode: LayerMode

    @State private var image: NSImage? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(ProgressView().scaleEffect(0.7))
                    }
                }
                .frame(width: width, height: height)
                .cornerRadius(6)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.14), radius: isSelected ? 5 : 2, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                )

                HStack(spacing: 4) {
                    if noteCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "note.text")
                                .font(.caption2)
                            if noteCount > 1 {
                                Text("\(noteCount)")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .foregroundColor(.orange)
                        .padding(4)
                        .background(.regularMaterial, in: Capsule())
                    }
                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(4)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .padding(4)
            }

            Text("\(pageIndex + 1)")
                .font(.system(size: 13, weight: .bold))
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
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No Table of Contents")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.bookmarks, children: \.children) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        if let page = item.pageNum {
                            Text("\(page)")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
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

// MARK: - Page-Associated Notes & Bookmarks Management View
struct BookmarksAndNotesView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedNoteId: UUID? = nil
    @State private var editingNoteText: String = ""
    @State private var editingNoteTitle: String = ""

    var body: some View {
        let currentNotes = viewModel.getPageNotes(for: viewModel.currentPageIndex)

        VStack(spacing: 0) {
            // Current Page Note Quick Editor
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Page \(viewModel.currentPageIndex + 1) Notes")
                        .font(.system(size: 13, weight: .bold))

                    Spacer()

                    Button(action: {
                        let newNote = viewModel.createPageNote(pageIndex: viewModel.currentPageIndex)
                        selectedNoteId = newNote.id
                        editingNoteTitle = newNote.title
                        editingNoteText = newNote.content
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add New Note to Page \(viewModel.currentPageIndex + 1)")

                    if let selectedId = selectedNoteId, let note = currentNotes.first(where: { $0.id == selectedId }) {
                        Button(action: {
                            viewModel.deletePageNote(note)
                            loadCurrentNote()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Selected Note")
                    }
                }

                if currentNotes.count > 1 {
                    Picker("Page Notes", selection: Binding(
                        get: { selectedNoteId ?? currentNotes.first?.id },
                        set: { newId in
                            selectedNoteId = newId
                            if let note = currentNotes.first(where: { $0.id == newId }) {
                                editingNoteTitle = note.title
                                editingNoteText = note.content
                            }
                        }
                    )) {
                        ForEach(currentNotes) { note in
                            Text(note.title).tag(Optional(note.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }

                TextField("Note Title...", text: $editingNoteTitle, onCommit: {
                    saveCurrentNote()
                })
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .medium))

                TextEditor(text: $editingNoteText)
                    .font(.system(size: 13))
                    .frame(height: 85)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .onChange(of: editingNoteText) { _, _ in
                        saveCurrentNote()
                    }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                // Section 1: User Bookmarks
                Section(header: Text("BOOKMARKS (\(viewModel.userBookmarks.count))").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)) {
                    if viewModel.userBookmarks.isEmpty {
                        Text("No bookmarks added")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.userBookmarks) { bm in
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)
                                Text(bm.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("P. \(bm.pageIndex + 1)")
                                    .font(.system(size: 12, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 3)
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

                // Section 2: Page Notes Directory
                Section(header: Text("PAGE NOTES DIRECTORY (\(viewModel.pageNotes.count))").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)) {
                    if viewModel.pageNotes.isEmpty {
                        Text("No notes written yet")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.pageNotes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 13))
                                        .foregroundColor(.orange)
                                    Text(note.title)
                                        .font(.system(size: 13, weight: .bold))
                                    Spacer()
                                    Text("P. \(note.pageIndex + 1)")
                                        .font(.system(size: 12, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }

                                if !note.content.isEmpty {
                                    Text(note.content)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.goToPage(note.pageIndex, animated: false)
                            }
                            .contextMenu {
                                Button("Delete Note", role: .destructive) {
                                    viewModel.deletePageNote(note)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .onAppear {
            loadCurrentNote()
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            loadCurrentNote()
        }
    }

    private func loadCurrentNote() {
        let notes = viewModel.getPageNotes(for: viewModel.currentPageIndex)
        if let first = notes.first {
            selectedNoteId = first.id
            editingNoteTitle = first.title
            editingNoteText = first.content
        } else {
            selectedNoteId = nil
            editingNoteTitle = "Page \(viewModel.currentPageIndex + 1) Note"
            editingNoteText = ""
        }
    }

    private func saveCurrentNote() {
        if let selectedId = selectedNoteId {
            viewModel.updatePageNote(id: selectedId, title: editingNoteTitle, content: editingNoteText)
        } else if !editingNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let note = viewModel.createPageNote(
                pageIndex: viewModel.currentPageIndex,
                title: editingNoteTitle,
                content: editingNoteText
            )
            selectedNoteId = note.id
        }
    }
}

// MARK: - Search Sidebar View with High Visibility
struct SearchSidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Search OCR text...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)

                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(8)

            if !viewModel.searchResults.isEmpty {
                HStack {
                    Text("\(viewModel.currentMatchIndex + 1) of \(viewModel.searchResults.count) matches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { viewModel.previousSearchMatch() }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.searchResults.isEmpty)

                    Button(action: { viewModel.nextSearchMatch() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.searchResults.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            Divider()

            if viewModel.isSearching {
                ProgressView("Searching OCR...")
                    .font(.system(size: 13))
                    .padding()
                Spacer()
            } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No matches found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                List(0..<viewModel.searchResults.count, id: \.self) { idx in
                    let result = viewModel.searchResults[idx]
                    let isSelected = idx == viewModel.currentMatchIndex

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Page \(result.page + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isSelected ? .accentColor : .primary)
                            Spacer()
                        }
                        Text(result.text)
                            .font(.system(size: 13))
                            .lineLimit(2)
                    }
                    .padding(6)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    .cornerRadius(5)
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
