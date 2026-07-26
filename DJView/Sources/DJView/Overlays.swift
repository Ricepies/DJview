import SwiftUI
import AppKit

public struct TextSelectionOverlayView: View {
    let pageIndex: Int
    let scaledSize: CGSize
    let originalSize: CGSize
    @ObservedObject var viewModel: AppViewModel

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil

    public init(pageIndex: Int, scaledSize: CGSize, originalSize: CGSize, viewModel: AppViewModel) {
        self.pageIndex = pageIndex
        self.scaledSize = scaledSize
        self.originalSize = originalSize
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // Search result match highlights on this page
                let searchMatches = viewModel.searchResults.filter { $0.page == pageIndex }
                ForEach(searchMatches) { match in
                    let rect = scaleRect(match.rect)
                    Rectangle()
                        .fill(Color.yellow.opacity(0.45))
                        .overlay(Rectangle().stroke(Color.orange, lineWidth: 1.5))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                // Current drag selection rectangle
                if let start = dragStart, let current = dragCurrent {
                    let selectionRect = rectFromPoints(start, current)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                        }
                        dragCurrent = value.location
                        extractSelectedText(start: dragStart!, end: value.location)
                    }
                    .onEnded { value in
                        if let start = dragStart {
                            extractSelectedText(start: start, end: value.location)
                        }
                        dragStart = nil
                        dragCurrent = nil
                    }
            )
        }
    }

    private func scaleRect(_ originalRect: CGRect) -> CGRect {
        guard originalSize.width > 0 && originalSize.height > 0 else { return .zero }
        let scaleX = scaledSize.width / originalSize.width
        let scaleY = scaledSize.height / originalSize.height
        return CGRect(
            x: originalRect.origin.x * scaleX,
            y: originalRect.origin.y * scaleY,
            width: originalRect.size.width * scaleX,
            height: originalRect.size.height * scaleY
        )
    }

    private func rectFromPoints(_ p1: CGPoint, _ p2: CGPoint) -> CGRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p1.x - p2.x)
        let h = abs(p1.y - p2.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func extractSelectedText(start: CGPoint, end: CGPoint) {
        let selRect = rectFromPoints(start, end)
        guard originalSize.width > 0 && originalSize.height > 0 else { return }

        let scaleX = originalSize.width / scaledSize.width
        let scaleY = originalSize.height / scaledSize.height

        let origSelRect = CGRect(
            x: selRect.origin.x * scaleX,
            y: selRect.origin.y * scaleY,
            width: selRect.size.width * scaleX,
            height: selRect.size.height * scaleY
        )

        var selectedWords: [String] = []

        func collectWords(from zone: TextZone) {
            if zone.rect.intersects(origSelRect) && !zone.text.isEmpty {
                if zone.kind == "word" || zone.kind == "line" {
                    selectedWords.append(zone.text)
                }
            }
            for child in zone.children {
                collectWords(from: child)
            }
        }

        for zone in viewModel.currentTextZones {
            collectWords(from: zone)
        }

        let combined = selectedWords.joined(separator: " ")
        if !combined.isEmpty {
            viewModel.selectedText = combined
            viewModel.copySelectedTextToClipboard()
        }
    }
}

// MARK: - Interactive Freely Draggable Sticky Notes Layer
public struct AnnotationOverlayView: View {
    let pageIndex: Int
    let scaledSize: CGSize
    @ObservedObject var viewModel: AppViewModel

    public init(pageIndex: Int, scaledSize: CGSize, viewModel: AppViewModel) {
        self.pageIndex = pageIndex
        self.scaledSize = scaledSize
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            let pageAnnotations = viewModel.annotations.filter { $0.pageIndex == pageIndex }
            ForEach(pageAnnotations) { ann in
                DraggableStickyNoteView(
                    annotation: ann,
                    scaledSize: scaledSize,
                    viewModel: viewModel
                )
            }
        }
    }
}

struct DraggableStickyNoteView: View {
    let annotation: Annotation
    let scaledSize: CGSize
    @ObservedObject var viewModel: AppViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var noteText: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        let noteWidth: CGFloat = max(220, annotation.width)
        let noteHeight: CGFloat = max(140, annotation.height)

        let posX = (annotation.x + Double(dragOffset.width))
        let posY = (annotation.y + Double(dragOffset.height))

        VStack(alignment: .leading, spacing: 6) {
            // Drag Handle Header
            HStack {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundColor(.black.opacity(0.6))
                Text("Sticky Note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                Button(action: {
                    viewModel.deleteAnnotation(annotation)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            Divider()
                .background(Color.black.opacity(0.2))

            // Note Text Field
            TextEditor(text: $noteText)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.black)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity)
                .onChange(of: noteText) { _, newText in
                    viewModel.updateAnnotationNoteText(id: annotation.id, newText: newText)
                }
        }
        .padding(10)
        .frame(width: noteWidth, height: noteHeight)
        .background(Color(hex: annotation.colorHex) ?? Color(red: 1.0, green: 0.96, blue: 0.62))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
        .position(x: CGFloat(posX) + noteWidth / 2, y: CGFloat(posY) + noteHeight / 2)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let finalX = annotation.x + Double(value.translation.width)
                    let finalY = annotation.y + Double(value.translation.height)
                    viewModel.updateAnnotationPosition(id: annotation.id, x: max(0, finalX), y: max(0, finalY))
                    dragOffset = .zero
                }
        )
        .onAppear {
            noteText = annotation.noteText
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
