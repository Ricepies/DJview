import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sidebar tab picker
            Picker("Sidebar View", selection: $viewModel.selectedSidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

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
        .frame(minWidth: 220)
    }
}

// MARK: - Thumbnails View
struct ThumbnailsView: View {
    @ObservedObject var viewModel: AppViewModel
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                        ThumbnailCell(
                            pageIndex: pageIndex,
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
                .padding(12)
            }
            .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

struct ThumbnailCell: View {
    let pageIndex: Int
    let isSelected: Bool
    let isBookmarked: Bool
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
                .frame(width: 100, height: 130)
                .cornerRadius(6)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.6) : Color.black.opacity(0.15), radius: isSelected ? 4 : 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.red)
                        .padding(4)
                        .shadow(radius: 2)
                }
            }

            Text("Page \(pageIndex + 1)")
                .font(.caption2)
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
        engine?.renderPage(pageIndex: pageIndex, targetWidth: 100, targetHeight: 130, layerMode: layerMode) { img in
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
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Table of Contents")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.bookmarks, children: \.children) { item in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.accentColor)
                        Text(item.title)
                            .font(.body)
                        Spacer()
                        if let page = item.pageNum {
                            Text("\(page)")
                                .font(.caption)
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

// MARK: - Search Sidebar View
struct SearchSidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search document...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(8)

            Divider()

            if viewModel.isSearching {
                ProgressView("Searching...")
                    .padding()
                Spacer()
            } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No matches found")
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                List(viewModel.searchResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Page \(result.page + 1)")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        Text(result.text)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.goToPage(result.page)
                    }
                }
                .listStyle(.sidebar)
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
                    .font(.headline)
                Spacer()
                Button(action: {
                    viewModel.addAnnotation(kind: .note, rect: CGRect(x: 50, y: 50, width: 150, height: 100), noteText: "New note")
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            Divider()

            if viewModel.annotations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No annotations yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.annotations) { ann in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: ann.kind == .highlight ? "highlighter" : "note.text")
                                    .foregroundColor(.accentColor)
                                Text("\(ann.kind.rawValue) (Page \(ann.pageIndex + 1))")
                                    .font(.caption)
                                    .bold()
                            }
                            if !ann.noteText.isEmpty {
                                Text(ann.noteText)
                                    .font(.subheadline)
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
