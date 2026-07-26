import SwiftUI
import AppKit

public struct ContinuousScrollView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var baseZoomScale: Double = 1.0

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
                    }
                }
                .padding(.vertical, 20)
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
            .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .top)
                }
            }
        }
    }
}

public struct SinglePageCanvasView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var baseZoomScale: Double = 1.0

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            SinglePageContainerView(
                pageIndex: viewModel.currentPageIndex,
                viewModel: viewModel
            )
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
    }
}

public struct MangaPageView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var baseZoomScale: Double = 1.0

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(spacing: 16) {
                let rightIndex = viewModel.currentPageIndex
                let leftIndex = viewModel.currentPageIndex + 1

                if leftIndex < viewModel.totalPages {
                    SinglePageContainerView(pageIndex: leftIndex, viewModel: viewModel)
                }

                SinglePageContainerView(pageIndex: rightIndex, viewModel: viewModel)
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
