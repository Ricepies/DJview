import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // macOS Preview style compact tab bar
            Picker("Sidebar View", selection: $viewModel.selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .tag(tab)
                        .help(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            switch viewModel.selectedSidebarTab {
            case .thumbnails:
                ThumbnailsView(viewModel: viewModel)
            case .toc:
                TOCView(viewModel: viewModel)
            case .search:
                SearchSidebarView(viewModel: viewModel)
            case .annotations:
                AnnotationsSidebarView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 350)
    }
}

// MARK: - Thumbnails View with Dynamic Layout Resizing
struct ThumbnailsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { geo in
            let availableWidth = max(100, geo.size.width - 24)
            // Calculate dynamic cell width & height to fit container width
            let targetCellWidth = min(availableWidth, max(90, availableWidth / floor(max(1, availableWidth / 110))))
            let cellHeight = targetCellWidth * 1.3
            let columns = [GridItem(.adaptive(minimum: targetCellWidth, maximum: targetCellWidth), spacing: 8)]

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                            ThumbnailCell(
                                pageIndex: pageIndex,
                                width: targetCellWidth,
                                height: cellHeight,
                                isSelected: viewModel.currentPageIndex == pageIndex,
                                isBookmarked: viewModel.userBookmarks.contains(pageIndex),
                                engine: viewModel.engine,
                                layerMode: viewModel.layerMode
                            )
                            .id(pageIndex)
                            .onTapGesture {
                                viewModel.goToPage(pageIndex)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                    withAnimation {
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
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(ProgressView().scaleEffect(0.6))
                    }
                }
                .frame(width: width, height: height)
                .cornerRadius(5)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.5) : Color.black.opacity(0.12), radius: isSelected ? 4 : 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                )

                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(3)
                        .shadow(radius: 1.5)
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
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(item.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        if let page = item.pageNum {
                            Text("\(page)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let page = item.pageNum, page >= 1 {
                            viewModel.goToPage(page - 1)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Search Sidebar View with Cmd+F Search Controls
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
                        viewModel.goToPage(result.page)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear {
            if viewModel.shouldFocusSearchField {
                isSearchFocused = true
                viewModel.shouldFocusSearchField = false
            }
        }
        .onChange(of: viewModel.shouldFocusSearchField) { _, newValue in
            if newValue {
                isSearchFocused = true
                viewModel.shouldFocusSearchField = false
            }
        }
    }
}

// MARK: - Annotations Sidebar View
struct AnnotationsSidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Annotations")
                    .font(.subheadline)
                    .bold()
                Spacer()
                Button(action: {
                    viewModel.addAnnotation(kind: .note, rect: CGRect(x: 50, y: 50, width: 150, height: 100), noteText: "New note")
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(8)

            Divider()

            if viewModel.annotations.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No annotations yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.annotations) { ann in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: ann.kind == .highlight ? "highlighter" : "note.text")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                                Text("\(ann.kind.rawValue) (P. \(ann.pageIndex + 1))")
                                    .font(.caption2)
                                    .bold()
                            }
                            if !ann.noteText.isEmpty {
                                Text(ann.noteText)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.goToPage(ann.pageIndex)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}
