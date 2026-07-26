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

// MARK: - Page Note Canvas Badge Indicator (Subtle Top-Right Corner Icon)
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
        ZStack(alignment: .topTrailing) {
            let notes = viewModel.getPageNotes(for: pageIndex)
            if !notes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                    Text("\(notes.count)")
                        .font(.caption2)
                        .bold()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(6)
                .shadow(radius: 2)
                .padding(10)
                .onTapGesture {
                    viewModel.selectedSidebarTab = .bookmarks
                }
            }
        }
    }
}
