import SwiftUI
import AppKit

public struct ContinuousScrollView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var baseZoomScale: Double = 1.0
    @State private var isProgrammaticScroll = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 20) {
                    ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                        SinglePageContainerView(
                            pageIndex: pageIndex,
                            viewModel: viewModel
                        )
                        .id(pageIndex)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: PagePositionPreferenceKey.self,
                                    value: [PagePositionData(pageIndex: pageIndex, minY: geo.frame(in: .named("scrollContainer")).minY, height: geo.size.height)]
                                )
                            }
                        )
                    }
                }
                .padding(.vertical, 20)
            }
            .coordinateSpace(name: "scrollContainer")
            .onPreferenceChange(PagePositionPreferenceKey.self) { positions in
                guard !isProgrammaticScroll else { return }
                if let mostVisible = positions.filter({ $0.minY <= 300 && ($0.minY + $0.height) >= 100 }).min(by: { abs($0.minY) < abs($1.minY) }) {
                    if viewModel.currentPageIndex != mostVisible.pageIndex {
                        DispatchQueue.main.async {
                            viewModel.setCurrentPageFromScroll(mostVisible.pageIndex)
                        }
                    }
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        if baseZoomScale == 1.0 {
                            baseZoomScale = viewModel.zoomScale
                        }
                        let updated = baseZoomScale * value
                        viewModel.setZoomScale(updated)
                    }
                    .onEnded { _ in
                        baseZoomScale = viewModel.zoomScale
                    }
            )
            .onAppear {
                let target = viewModel.currentPageIndex
                isProgrammaticScroll = true
                proxy.scrollTo(target, anchor: .top)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(target, anchor: .top)
                    isProgrammaticScroll = false
                }
            }
            .onChange(of: viewModel.targetJumpPageIndex) { _, targetIndex in
                guard let targetIndex = targetIndex else { return }
                isProgrammaticScroll = true

                if viewModel.isDirectJump {
                    proxy.scrollTo(targetIndex, anchor: .top)
                    isProgrammaticScroll = false
                    viewModel.targetJumpPageIndex = nil
                    viewModel.isDirectJump = false
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(targetIndex, anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        isProgrammaticScroll = false
                        viewModel.targetJumpPageIndex = nil
                    }
                }
            }
        }
    }
}

struct PagePositionData: Equatable {
    let pageIndex: Int
    let minY: CGFloat
    let height: CGFloat
}

struct PagePositionPreferenceKey: PreferenceKey {
    static var defaultValue: [PagePositionData] = []
    static func reduce(value: inout [PagePositionData], nextValue: () -> [PagePositionData]) {
        value.append(contentsOf: nextValue())
    }
}

public struct SinglePageCanvasView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var baseZoomScale: Double = 1.0
    @State private var eventMonitor: Any? = nil
    @State private var hasTriggeredInCurrentGesture: Bool = false
    @State private var lastFlipTime: Date = .distantPast

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            ZStack {
                SinglePageContainerView(
                    pageIndex: viewModel.currentPageIndex,
                    viewModel: viewModel
                )
                .id("single_\(viewModel.currentPageIndex)")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if baseZoomScale == 1.0 {
                        baseZoomScale = viewModel.zoomScale
                    }
                    let updated = baseZoomScale * value
                    viewModel.setZoomScale(updated)
                }
                .onEnded { _ in
                    baseZoomScale = viewModel.zoomScale
                }
        )
        .onAppear {
            setupTrackpadMonitor()
        }
        .onDisappear {
            removeTrackpadMonitor()
        }
    }

    private func setupTrackpadMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard viewModel.layoutMode == .singlePage else { return event }

            // Ignore momentum/inertia events from trackpad deceleration
            if event.momentumPhase != [] {
                return nil
            }

            if event.phase == .ended || event.phase == .cancelled {
                hasTriggeredInCurrentGesture = false
                return event
            }

            if event.phase == .began {
                hasTriggeredInCurrentGesture = false
            }

            let now = Date()
            guard !hasTriggeredInCurrentGesture && now.timeIntervalSince(lastFlipTime) > 0.40 else {
                return nil
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            if dx < -5.0 || dy < -5.0 {
                hasTriggeredInCurrentGesture = true
                lastFlipTime = now
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage()
                    }
                }
                return nil
            } else if dx > 5.0 || dy > 5.0 {
                hasTriggeredInCurrentGesture = true
                lastFlipTime = now
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage()
                    }
                }
                return nil
            }
            return event
        }
    }

    private func removeTrackpadMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

public struct MangaPageView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var baseZoomScale: Double = 1.0
    @State private var eventMonitor: Any? = nil
    @State private var hasTriggeredInCurrentGesture: Bool = false
    @State private var lastFlipTime: Date = .distantPast

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(spacing: 16) {
                // Right-to-Left Manga Layout: right page is index, left page is index + 1
                let rightIndex = viewModel.currentPageIndex
                let leftIndex = viewModel.currentPageIndex + 1

                if leftIndex < viewModel.totalPages {
                    SinglePageContainerView(pageIndex: leftIndex, viewModel: viewModel)
                        .id("manga_left_\(leftIndex)")
                }

                SinglePageContainerView(pageIndex: rightIndex, viewModel: viewModel)
                    .id("manga_right_\(rightIndex)")
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if baseZoomScale == 1.0 {
                        baseZoomScale = viewModel.zoomScale
                    }
                    let updated = baseZoomScale * value
                    viewModel.setZoomScale(updated)
                }
                .onEnded { _ in
                    baseZoomScale = viewModel.zoomScale
                }
        )
        .onAppear {
            setupTrackpadMonitor()
        }
        .onDisappear {
            removeTrackpadMonitor()
        }
    }

    private func setupTrackpadMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard viewModel.layoutMode == .manga else { return event }

            // Ignore momentum/inertia events from trackpad deceleration
            if event.momentumPhase != [] {
                return nil
            }

            if event.phase == .ended || event.phase == .cancelled {
                hasTriggeredInCurrentGesture = false
                return event
            }

            if event.phase == .began {
                hasTriggeredInCurrentGesture = false
            }

            let now = Date()
            guard !hasTriggeredInCurrentGesture && now.timeIntervalSince(lastFlipTime) > 0.40 else {
                return nil
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            if dx < -5.0 || dy < -5.0 {
                hasTriggeredInCurrentGesture = true
                lastFlipTime = now
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.nextPage()
                    }
                }
                return nil
            } else if dx > 5.0 || dy > 5.0 {
                hasTriggeredInCurrentGesture = true
                lastFlipTime = now
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.previousPage()
                    }
                }
                return nil
            }
            return event
        }
    }

    private func removeTrackpadMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

public struct SinglePageContainerView: View {
    let pageIndex: Int
    @ObservedObject var viewModel: AppViewModel

    @State private var image: NSImage? = nil
    @State private var rawData: Data? = nil
    @State private var renderWidth: Int = 0
    @State private var renderHeight: Int = 0

    public init(pageIndex: Int, viewModel: AppViewModel) {
        self.pageIndex = pageIndex
        self.viewModel = viewModel
    }

    public var body: some View {
        let dim = viewModel.engine?.getPageDimension(pageIndex: pageIndex) ?? (600, 800, 72)
        let scaledWidth = CGFloat(dim.width) * CGFloat(viewModel.zoomScale)
        let scaledHeight = CGFloat(dim.height) * CGFloat(viewModel.zoomScale)

        ZStack {
            if viewModel.useMetalRenderer {
                MetalPageView(
                    rawData: rawData,
                    width: renderWidth,
                    height: renderHeight,
                    shaderMode: viewModel.shaderMode
                )
                .frame(width: scaledWidth, height: scaledHeight)
                .cornerRadius(4)
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            } else {
                Group {
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: scaledWidth, height: scaledHeight)
                .cornerRadius(4)
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            }

            // Interactive Text Selection & Search Match Highlights
            TextSelectionOverlayView(
                pageIndex: pageIndex,
                scaledSize: CGSize(width: scaledWidth, height: scaledHeight),
                originalSize: CGSize(width: CGFloat(dim.width), height: CGFloat(dim.height)),
                viewModel: viewModel
            )
            .frame(width: scaledWidth, height: scaledHeight)

            // Annotation Drawing Layer
            AnnotationOverlayView(
                pageIndex: pageIndex,
                scaledSize: CGSize(width: scaledWidth, height: scaledHeight),
                viewModel: viewModel
            )
            .frame(width: scaledWidth, height: scaledHeight)
        }
        .onAppear {
            loadPageData()
            let dim = viewModel.engine?.getPageDimension(pageIndex: pageIndex) ?? (600, 800, 72)
            let targetW = Int(CGFloat(dim.width) * CGFloat(viewModel.zoomScale))
            let targetH = Int(CGFloat(dim.height) * CGFloat(viewModel.zoomScale))
            viewModel.engine?.prefetchPages(around: pageIndex, targetWidth: targetW, targetHeight: targetH, layerMode: viewModel.layerMode)
        }
        .onChange(of: pageIndex) { _, _ in
            loadPageData()
        }
        .onChange(of: viewModel.layerMode) { _, _ in
            loadPageData()
        }
        .onChange(of: viewModel.zoomScale) { _, _ in
            loadPageData()
        }
    }

    private func loadPageData() {
        let dim = viewModel.engine?.getPageDimension(pageIndex: pageIndex) ?? (600, 800, 72)
        let targetW = Int(CGFloat(dim.width) * CGFloat(viewModel.zoomScale))
        let targetH = Int(CGFloat(dim.height) * CGFloat(viewModel.zoomScale))

        if viewModel.useMetalRenderer {
            viewModel.engine?.renderPageRawRGBA(pageIndex: pageIndex, targetWidth: targetW, targetHeight: targetH, layerMode: viewModel.layerMode) { data, w, h in
                self.rawData = data
                self.renderWidth = w
                self.renderHeight = h
            }
        } else {
            viewModel.engine?.renderPage(pageIndex: pageIndex, targetWidth: targetW, targetHeight: targetH, layerMode: viewModel.layerMode) { img in
                self.image = img
            }
        }
    }
}
