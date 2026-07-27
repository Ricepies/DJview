import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct MainView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isTargetedForDrop = false
    @State private var isSettingsSheetPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    public init(viewModel: AppViewModel = AppViewModel()) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Fixed-width sidebar panel — slides in/out via frame width, never reflows toolbar
            if viewModel.isSidebarVisible {
                SidebarView(viewModel: viewModel)
                    .frame(width: 220)
                    .transition(.move(edge: .leading))

                Divider()
            }

            VStack(spacing: 0) {
                // PDF2DjVu Conversion Status Bar (Full Top Banner)
                if viewModel.isPDFConverting && !viewModel.isPDFConversionMinimized {
                    PDFConversionTopStatusBar(viewModel: viewModel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

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
                            EmptyStateView(
                                recentFiles: viewModel.recentFiles,
                                onOpen: selectAndOpenDocument,
                                onConvertPDF: selectAndConvertPDF,
                                onOpenRecent: { url in viewModel.openDocument(at: url) },
                                onClearRecents: { viewModel.clearRecentFiles() }
                            )
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
            .animation(.easeInOut(duration: 0.2), value: viewModel.isPDFConverting)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isPDFConversionMinimized)
            .animation(.easeInOut(duration: 0.18), value: viewModel.isSearchPopupVisible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.isSidebarVisible)
        .toolbar {
            CustomToolbar(
                viewModel: viewModel,
                onOpenDocument: selectAndOpenDocument,
                onOpenSettings: { isSettingsSheetPresented = true },
                onOpenExportModal: { viewModel.isExportModalPresented = true }
            )
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isExportModalPresented) {
            DocumentConversionSheet(viewModel: viewModel)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    let ext = url.pathExtension.lowercased()
                    if ext == "djvu" || ext == "djv" {
                        DispatchQueue.main.async {
                            viewModel.openDocument(at: url)
                        }
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
                        viewModel.previousPage(vertical: false)
                    }
                }) { EmptyView() }.keyboardShortcut(.leftArrow, modifiers: [])

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage(vertical: false)
                    }
                }) { EmptyView() }.keyboardShortcut(.rightArrow, modifiers: [])

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage(vertical: true)
                    }
                }) { EmptyView() }.keyboardShortcut(.upArrow, modifiers: [])

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage(vertical: true)
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

                // Cmd+E: Open Document Conversion Modal
                Button(action: { viewModel.isExportModalPresented = true }) { EmptyView() }.keyboardShortcut("e", modifiers: [.command, .shift])

                // Cmd+Shift+S: Toggle Sidebar
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.isSidebarVisible.toggle()
                    }
                }) { EmptyView() }.keyboardShortcut("s", modifiers: [.command, .shift])

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
        panel.title = "Open DjVu Document"
        panel.message = "Choose a DjVu file (.djvu, .djv) to read"
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

    private func selectAndConvertPDF() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select PDF / Manga Document to Convert"
        openPanel.message = "Choose a PDF file (.pdf) to encode into DjVu format with shared symbol dictionary"
        openPanel.allowedContentTypes = [.pdf]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.prompt = "Select PDF"

        if openPanel.runModal() == .OK, let pdfURL = openPanel.url {
            promptSaveAndConvertPDF(pdfURL: pdfURL)
        }
    }

    private func promptSaveAndConvertPDF(pdfURL: URL) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Converted DjVu Document"
        savePanel.message = "Choose target destination for the encoded DjVu document"
        savePanel.nameFieldStringValue = pdfURL.deletingPathExtension().lastPathComponent + ".djvu"
        savePanel.directoryURL = pdfURL.deletingLastPathComponent()
        savePanel.prompt = "Save DjVu"

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            viewModel.convertPDFToDjVu(pdfURL: pdfURL, targetURL: targetURL, qualityMode: 0) // 0 = Lossless JB2 Manga
        }
    }
}

// MARK: - Full Top Status Bar for PDF2DjVu Conversion
struct PDFConversionTopStatusBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProgressView(value: viewModel.exportProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 180)

                Text(viewModel.exportStatusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(Int(viewModel.exportProgress * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.accentColor)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.togglePDFConversionMinimized()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down.square.fill")
                            .font(.system(size: 13))
                        Text("Run in Background")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.cancelPDFConversion()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
    }
}

// MARK: - Non-Intrusive Floating Background Task Pill
struct PDFConversionMinimizedPill: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

            Text("\(viewModel.exportStatusText) (\(Int(viewModel.exportProgress * 100))%)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.togglePDFConversionMinimized()
                }
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        )
        .overlay(
            Capsule()
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}



// MARK: - Refined & Compact Document Conversion Popup (Zero Overflow)
struct DocumentConversionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedFormat: ExportDocumentFormat = .pdf
    @State private var rangeOption: Int = 0 // 0 = All, 1 = Current Page, 2 = Custom Range
    @State private var customStartPage: Int = 1
    @State private var customEndPage: Int = 1
    @State private var qualityScale: Double = 1.5

    var body: some View {
        VStack(spacing: 16) {
            // Header Bar
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Convert Document")
                        .font(.headline)
                        .bold()
                    Text("Export DjVu pages to PDF, EPUB, CBZ, TIFF, or PNG")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if viewModel.isExporting {
                VStack(spacing: 14) {
                    ProgressView(value: viewModel.exportProgress)
                        .progressViewStyle(.linear)

                    Text(viewModel.exportStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 14) {
                    // Format Cards Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export Format")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(ExportDocumentFormat.allCases) { fmt in
                                Button(action: { selectedFormat = fmt }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: fmt.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(selectedFormat == fmt ? .accentColor : .primary)
                                        Text(fmt.id.components(separatedBy: " (").first ?? fmt.rawValue)
                                            .font(.system(size: 12, weight: selectedFormat == fmt ? .semibold : .regular))
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(selectedFormat == fmt ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(selectedFormat == fmt ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Page Range Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Page Range")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Picker("", selection: $rangeOption) {
                                Text("All (\(viewModel.totalPages))").tag(0)
                                Text("Page \(viewModel.currentPageIndex + 1)").tag(1)
                                Text("Custom").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)

                            if rangeOption == 2 {
                                HStack(spacing: 4) {
                                    TextField("1", value: $customStartPage, formatter: NumberFormatter())
                                        .frame(width: 44)
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                    Text("–")
                                        .font(.caption)
                                    TextField("\(viewModel.totalPages)", value: $customEndPage, formatter: NumberFormatter())
                                        .frame(width: 44)
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }

                    // Quality / Resolution Scale
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Image Resolution")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $qualityScale) {
                            Text("1.0x Standard").tag(1.0)
                            Text("1.5x Crisp").tag(1.5)
                            Text("2.0x Retina").tag(2.0)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                }

                Divider()

                // Bottom Action Footer
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: triggerExportPanel) {
                        Label("Convert & Export...", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear {
            customStartPage = 1
            customEndPage = max(1, viewModel.totalPages)
        }
    }

    private func triggerExportPanel() {
        let docTitle = viewModel.documentURL?.deletingPathExtension().lastPathComponent ?? "Exported_Document"

        var sPage = 0
        var ePage = max(0, viewModel.totalPages - 1)

        if rangeOption == 1 {
            sPage = viewModel.currentPageIndex
            ePage = viewModel.currentPageIndex
        } else if rangeOption == 2 {
            sPage = max(0, min(viewModel.totalPages - 1, customStartPage - 1))
            ePage = max(sPage, min(viewModel.totalPages - 1, customEndPage - 1))
        }

        if selectedFormat == .pngFolder {
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = true
            openPanel.canChooseFiles = false
            openPanel.canCreateDirectories = true
            openPanel.prompt = "Export PNG Series To"
            openPanel.directoryURL = viewModel.documentURL?.deletingLastPathComponent()

            if openPanel.runModal() == .OK, let targetFolder = openPanel.url {
                let dest = targetFolder.appendingPathComponent("\(docTitle)_PNG_Series")
                viewModel.convertDocumentBatch(
                    format: selectedFormat,
                    startPage: sPage,
                    endPage: ePage,
                    qualityScale: qualityScale,
                    targetURL: dest
                )
            }
        } else {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = "\(docTitle).\(selectedFormat.fileExtension)"
            savePanel.directoryURL = viewModel.documentURL?.deletingLastPathComponent()

            if savePanel.runModal() == .OK, let targetFile = savePanel.url {
                viewModel.convertDocumentBatch(
                    format: selectedFormat,
                    startPage: sPage,
                    endPage: ePage,
                    qualityScale: qualityScale,
                    targetURL: targetFile
                )
            }
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
        VStack(spacing: 8) {
            // Refined Non-Intrusive Export Progress Banner (Centered Above HUD)
            if viewModel.isExporting || (viewModel.isPDFConverting && viewModel.isPDFConversionMinimized) {
                HStack(spacing: 10) {
                    ProgressView(value: viewModel.exportProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 130)

                    Text("\(viewModel.exportStatusText) (\(Int(viewModel.exportProgress * 100))%)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isExportModalPresented = true
                        }
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Expand Conversion Dialog")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Canvas Control Bar (Page Stepper, Zoom, Layout Switcher)
            HStack(spacing: 14) {
            // Page Navigation Stepper
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage(vertical: false)
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
                        viewModel.nextPage(vertical: false)
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

// MARK: - Empty State & Recently Opened System Welcome Screen with PDF2DjVu
struct EmptyStateView: View {
    let recentFiles: [URL]
    let onOpen: () -> Void
    let onConvertPDF: () -> Void
    let onOpenRecent: (URL) -> Void
    let onClearRecents: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 76))
                .foregroundColor(.accentColor)

            VStack(spacing: 6) {
                Text("DJView Reader")
                    .font(.largeTitle)
                    .bold()
                Text("High-performance native macOS DjVu viewer with Metal acceleration")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 14) {
                Button(action: onOpen) {
                    Label("Open DjVu File...", systemImage: "arrow.up.doc.fill")
                        .font(.title3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onConvertPDF) {
                    Label("Convert PDF to DjVu...", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                        .font(.title3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recently Opened")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear", action: onClearRecents)
                            .font(.system(size: 12))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recentFiles, id: \.self) { url in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.accentColor)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(url.deletingLastPathComponent().path)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onOpenRecent(url)
                            }
                        }
                    }
                }
                .frame(maxWidth: 480)
                .padding(.top, 10)
            }

            Text("Or drag and drop a .djvu / .pdf file anywhere")
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
    let onOpenExportModal: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            // Fixed sidebar toggle — always present, never shifts
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    viewModel.isSidebarVisible.toggle()
                }
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .symbolVariant(viewModel.isSidebarVisible ? .fill : .none)
            }
            .help("Toggle Sidebar (Cmd+Shift+S)")

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

                // Top Bar: Convert & Export Document Modal Button
                Button(action: onOpenExportModal) {
                    Image(systemName: "square.and.arrow.up.on.square")
                        .font(.system(size: 15, weight: .medium))
                }
                .help("Convert & Export Document (Cmd+Shift+E)")

                // Settings Button
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .help("Preferences (Cmd+,)")
            }
        }
    }
}
