import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct MainView: View {
    @StateObject var viewModel = AppViewModel()
    @State private var isTargetedForDrop = false
    @State private var isSettingsSheetPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    public var body: some View {
        NavigationSplitView {
            if viewModel.isSidebarVisible {
                SidebarView(viewModel: viewModel)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        } detail: {
            VStack(spacing: 0) {
                // Expandable Page Note Taking Drawer (Activated & Closed by Top Note Button)
                if viewModel.isNoteTakingActive {
                    PageNoteTopDrawer(viewModel: viewModel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZStack(alignment: .bottom) {
                    ZStack(alignment: .topTrailing) {
                        if viewModel.engine != nil {
                            Group {
                                switch viewModel.layoutMode {
                                case .continuous:
                                    ContinuousScrollView(viewModel: viewModel)
                                case .singlePage:
                                    SinglePageCanvasView(viewModel: viewModel)
                                case .manga:
                                    MangaPageView(viewModel: viewModel)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if viewModel.isNoteTakingActive {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.closeNoteTaking()
                                    }
                                }
                            }
                        } else {
                            EmptyStateView {
                                selectAndOpenDocument()
                            }
                        }

                        // Native macOS Preview-style Top-Right Search Bar
                        if viewModel.isSearchPopupVisible {
                            NativeSearchPopupBar(viewModel: viewModel, isFocused: $isSearchFieldFocused)
                                .padding(.top, 12)
                                .padding(.trailing, 18)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(100)
                        }
                    }

                    // Sleek Floating Canvas Control Pill (Bottom-Center HUD)
                    if viewModel.engine != nil {
                        CanvasFloatingHUD(viewModel: viewModel)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(200)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isNoteTakingActive)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isSidebarVisible)
            .animation(.easeInOut(duration: 0.18), value: viewModel.isSearchPopupVisible)
            .toolbar {
                CustomToolbar(viewModel: viewModel, onOpenDocument: selectAndOpenDocument, onOpenSettings: { isSettingsSheetPresented = true })
            }
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            SettingsView(viewModel: viewModel)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.pathExtension.lowercased() == "djvu" || url.pathExtension.lowercased() == "djv" {
                    DispatchQueue.main.async {
                        viewModel.openDocument(at: url)
                    }
                }
            }
            return true
        }
        .background(
            ZStack {
                // Page Flipping Shortcuts: Left/Right & Up/Down Arrows
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage()
                    }
                }) { EmptyView() }.keyboardShortcut(.leftArrow, modifiers: [])

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage()
                    }
                }) { EmptyView() }.keyboardShortcut(.rightArrow, modifiers: [])

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage()
                    }
                }) { EmptyView() }.keyboardShortcut(.upArrow, modifiers: [])

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage()
                    }
                }) { EmptyView() }.keyboardShortcut(.downArrow, modifiers: [])

                // Zoom Shortcuts: Cmd+ / Cmd= and Cmd-
                Button(action: { viewModel.zoomIn() }) { EmptyView() }.keyboardShortcut("=", modifiers: .command)
                Button(action: { viewModel.zoomIn() }) { EmptyView() }.keyboardShortcut("+", modifiers: .command)
                Button(action: { viewModel.zoomOut() }) { EmptyView() }.keyboardShortcut("-", modifiers: .command)
                Button(action: { viewModel.setZoomScale(1.0) }) { EmptyView() }.keyboardShortcut("0", modifiers: .command)

                // Cmd+F: Search & Focus
                Button(action: {
                    viewModel.activateSearch()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isSearchFieldFocused = true
                    }
                }) { EmptyView() }.keyboardShortcut("f", modifiers: .command)

                // Cmd+D: Bookmark Page
                Button(action: { viewModel.toggleBookmarkCurrentPage() }) { EmptyView() }.keyboardShortcut("d", modifiers: .command)

                // Cmd+Shift+N: Toggle Note Taking Mode
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleNoteTaking()
                    }
                }) { EmptyView() }.keyboardShortcut("n", modifiers: [.command, .shift])

                // Cmd+,: Open Settings
                Button(action: { isSettingsSheetPresented = true }) { EmptyView() }.keyboardShortcut(",", modifiers: .command)

                // Cmd+1/2/3: Layout Mode Switchers
                Button(action: { viewModel.layoutMode = .continuous }) { EmptyView() }.keyboardShortcut("1", modifiers: .command)
                Button(action: { viewModel.layoutMode = .singlePage }) { EmptyView() }.keyboardShortcut("2", modifiers: .command)
                Button(action: { viewModel.layoutMode = .manga }) { EmptyView() }.keyboardShortcut("3", modifiers: .command)
            }
            .opacity(0)
        )
    }

    private func selectAndOpenDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "djvu") ?? .data,
            UTType(filenameExtension: "djv") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.openDocument(at: url)
        }
    }
}

// MARK: - Page Note Taking Drawer with Multiple Notes Support
struct PageNoteTopDrawer: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedNoteId: UUID? = nil
    @State private var noteTitle: String = ""
    @State private var noteContent: String = ""

    var body: some View {
        let currentNotes = viewModel.getPageNotes(for: viewModel.currentPageIndex)

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text("Notes for Page \(viewModel.currentPageIndex + 1)")
                        .font(.system(size: 14, weight: .bold))

                    Spacer()

                    // Add New Note for Current Page Button
                    Button(action: {
                        let newNote = viewModel.createPageNote(pageIndex: viewModel.currentPageIndex)
                        selectedNoteId = newNote.id
                        noteTitle = newNote.title
                        noteContent = newNote.content
                    }) {
                        Label("Add Note", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderless)

                    if let selectedId = selectedNoteId, let note = currentNotes.first(where: { $0.id == selectedId }) {
                        Button(action: {
                            viewModel.deletePageNote(note)
                            loadCurrentNote()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Note")
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.closeNoteTaking()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Save & Close Note Drawer")
                }

                // Picker for Multiple Notes on Same Page
                if currentNotes.count > 1 {
                    Picker("Page Notes", selection: Binding(
                        get: { selectedNoteId ?? currentNotes.first?.id },
                        set: { newId in
                            selectedNoteId = newId
                            if let note = currentNotes.first(where: { $0.id == newId }) {
                                noteTitle = note.title
                                noteContent = note.content
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

                HStack(spacing: 10) {
                    TextField("Note Title...", text: $noteTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 200)

                    TextEditor(text: $noteContent)
                        .font(.system(size: 13))
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
        .onAppear {
            loadCurrentNote()
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            loadCurrentNote()
        }
        .onChange(of: noteContent) { _, _ in
            saveCurrentNote()
        }
        .onChange(of: noteTitle) { _, _ in
            saveCurrentNote()
        }
    }

    private func loadCurrentNote() {
        let notes = viewModel.getPageNotes(for: viewModel.currentPageIndex)
        if let first = notes.first {
            selectedNoteId = first.id
            noteTitle = first.title
            noteContent = first.content
        } else {
            let newNote = viewModel.createPageNote(pageIndex: viewModel.currentPageIndex)
            selectedNoteId = newNote.id
            noteTitle = newNote.title
            noteContent = newNote.content
        }
    }

    private func saveCurrentNote() {
        if let selectedId = selectedNoteId {
            viewModel.updatePageNote(id: selectedId, title: noteTitle, content: noteContent)
        }
    }
}

// MARK: - Floating Canvas HUD Control Pill (Bottom-Center)
struct CanvasFloatingHUD: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Page Navigation Stepper
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.currentPageIndex <= 0)

                Text("\(viewModel.currentPageIndex + 1) / \(viewModel.totalPages)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.currentPageIndex >= viewModel.totalPages - 1)
            }

            Divider()
                .frame(height: 16)

            // Zoom Controls
            HStack(spacing: 8) {
                Button(action: { viewModel.zoomOut() }) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)

                Text("\(Int(viewModel.zoomScale * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 44)
                    .onTapGesture {
                        viewModel.setZoomScale(1.0)
                    }

                Button(action: { viewModel.zoomIn() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 16)

            // Layout Mode Switcher Segment
            HStack(spacing: 6) {
                ForEach(ViewLayoutMode.allCases) { mode in
                    Button(action: { viewModel.layoutMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: viewModel.layoutMode == mode ? .bold : .regular))
                            .foregroundColor(viewModel.layoutMode == mode ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(mode.rawValue)
                }
            }

            Divider()
                .frame(height: 16)

            // Visual Settings & Filters Menu
            Menu {
                Section("DjVu Layer Mode") {
                    ForEach(LayerMode.allCases) { layer in
                        Button(action: { viewModel.layerMode = layer }) {
                            Label(layer.title, systemImage: layer.icon)
                        }
                    }
                }
                Section("Metal Color Shader") {
                    ForEach(ColorShaderMode.allCases) { mode in
                        Button(action: { viewModel.shaderMode = mode }) {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 13))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .help("Layer & Color Filter Controls")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Native Preview-style Search Bar with Larger Fonts & Focus
struct NativeSearchPopupBar: View {
    @ObservedObject var viewModel: AppViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .medium))

            TextField("Search", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .frame(width: 180)
                .focused(isFocused)
                .onSubmit {
                    viewModel.nextSearchMatch()
                }

            if !viewModel.searchResults.isEmpty {
                Text("\(viewModel.currentMatchIndex + 1) of \(viewModel.searchResults.count)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            } else if viewModel.isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            Divider()
                .frame(height: 16)

            HStack(spacing: 4) {
                Button(action: { viewModel.previousSearchMatch() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.searchResults.isEmpty)

                Button(action: { viewModel.nextSearchMatch() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.searchResults.isEmpty)
            }

            Button(action: {
                viewModel.dismissSearchPopup()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            isFocused.wrappedValue = true
        }
        .onChange(of: viewModel.shouldFocusSearchField) { _, newValue in
            if newValue {
                isFocused.wrappedValue = true
                viewModel.shouldFocusSearchField = false
            }
        }
    }
}

// MARK: - Settings Sheet
struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("DJView Preferences")
                .font(.title3)
                .bold()

            Form {
                Toggle("Use Metal GPU Renderer", isOn: $viewModel.useMetalRenderer)
                    .font(.body)
                Picker("Default Layout Mode", selection: $viewModel.layoutMode) {
                    ForEach(ViewLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .font(.body)
                Picker("Default Layer", selection: $viewModel.layerMode) {
                    ForEach(LayerMode.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .font(.body)
            }
            .padding()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 400, height: 250)
    }
}

struct EmptyStateView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 84))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("DJView Reader")
                    .font(.largeTitle)
                    .bold()
                Text("High-performance native macOS DjVu viewer with Metal acceleration")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Button(action: onOpen) {
                Label("Open DjVu File...", systemImage: "arrow.up.doc.fill")
                    .font(.title3)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Or drag and drop a .djvu file anywhere")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }
}

struct CustomToolbar: ToolbarContent {
    @ObservedObject var viewModel: AppViewModel
    let onOpenDocument: () -> Void
    let onOpenSettings: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: onOpenDocument) {
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .medium))
            }
            .help("Open DjVu File (Cmd+O)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.engine != nil {
                // Top Bar: Bookmark Button
                Button(action: { viewModel.toggleBookmarkCurrentPage() }) {
                    Image(systemName: viewModel.isPageBookmarked(viewModel.currentPageIndex) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(viewModel.isPageBookmarked(viewModel.currentPageIndex) ? .red : .primary)
                }
                .help("Bookmark Current Page (Cmd+D)")

                // Top Bar: Note Taking Activation Button (Toggles Drawer On/Off)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleNoteTaking()
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(viewModel.isNoteTakingActive ? .accentColor : .primary)
                }
                .help("Toggle Page Note Drawer (Cmd+Shift+N)")

                // Top Bar: Search Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if viewModel.isSearchPopupVisible {
                            viewModel.dismissSearchPopup()
                        } else {
                            viewModel.activateSearch()
                        }
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                }
                .help("Search Document (Cmd+F)")

                // Settings Button
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .help("Preferences (Cmd+,)")

                // Export Page Button
                Menu {
                    Button("Export Page as PNG...") {
                        exportPage(format: 0)
                    }
                    Button("Export Page as JPEG...") {
                        exportPage(format: 1)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                }
                .help("Export Page")
            }
        }
    }

    private func exportPage(format: Int) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format == 0 ? .png : .jpeg]
        savePanel.nameFieldStringValue = "Page_\(viewModel.currentPageIndex + 1).\(format == 0 ? "png" : "jpg")"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            _ = viewModel.exportCurrentPage(format: format, targetURL: url)
        }
    }
}
