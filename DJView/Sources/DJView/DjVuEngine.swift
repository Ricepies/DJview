import Foundation
import AppKit
import CoreGraphics
import CDjVuBridge

public final class DjVuEngine {
    public let docPtr: OpaquePointer
    private let pageCache = NSCache<NSString, NSImage>()
    private let rawDataCache = NSCache<NSString, NSData>()

    public var pageCount: Int {
        Int(djvu_doc_page_count(docPtr))
    }

    public init?(filePath: String) {
        guard let ctx = djvu_doc_open(filePath) else {
            return nil
        }
        self.docPtr = ctx

        // Configure cache limits for high-performance lazy loading
        pageCache.countLimit = 40
        rawDataCache.countLimit = 40
    }

    deinit {
        djvu_doc_free(docPtr)
    }

    public func getPageDimension(pageIndex: Int) -> (width: Int, height: Int, dpi: Int)? {
        var w: UInt32 = 0
        var h: UInt32 = 0
        var dpi: UInt16 = 0
        let res = djvu_doc_get_page_dimension(docPtr, UInt32(pageIndex), &w, &h, &dpi)
        guard res == 0 else { return nil }
        return (Int(w), Int(h), Int(dpi))
    }

    public func renderPage(
        pageIndex: Int,
        targetWidth: Int = 0,
        targetHeight: Int = 0,
        layerMode: LayerMode = .composite,
        completion: @escaping (NSImage?) -> Void
    ) {
        let cacheKey = "\(pageIndex)_\(targetWidth)_\(targetHeight)_\(layerMode.rawValue)" as NSString
        if let cached = pageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        let ctx = self.docPtr
        DispatchQueue.global(qos: .userInitiated).async {
            guard pageIndex >= 0 && pageIndex < Int(djvu_doc_page_count(ctx)) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let (dw, dh, _) = self.getPageDimension(pageIndex: pageIndex) ?? (300, 400, 72)
            let w = targetWidth > 0 ? targetWidth : dw
            let h = targetHeight > 0 ? targetHeight : dh

            let byteCount = w * h * 4
            var buffer = [UInt8](repeating: 0, count: byteCount)
            var actualW: UInt32 = 0
            var actualH: UInt32 = 0

            let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return -1 }
                return djvu_doc_render_page_rgba(ctx, UInt32(pageIndex), UInt32(w), UInt32(h), UInt32(layerMode.rawValue), base, &actualW, &actualH)
            }

            guard res == 0, actualW > 0, actualH > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let finalW = Int(actualW)
            let finalH = Int(actualH)

            let data = Data(buffer.prefix(finalW * finalH * 4))
            guard let provider = CGDataProvider(data: data as CFData) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)

            guard let cgImage = CGImage(
                width: finalW,
                height: finalH,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: finalW * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let img = NSImage(cgImage: cgImage, size: NSSize(width: finalW, height: finalH))
            self.pageCache.setObject(img, forKey: cacheKey)

            DispatchQueue.main.async {
                completion(img)
            }
        }
    }

    public func renderPageRawRGBA(
        pageIndex: Int,
        targetWidth: Int = 0,
        targetHeight: Int = 0,
        layerMode: LayerMode = .composite,
        completion: @escaping (Data?, Int, Int) -> Void
    ) {
        let cacheKey = "raw_\(pageIndex)_\(targetWidth)_\(targetHeight)_\(layerMode.rawValue)" as NSString
        if let cached = rawDataCache.object(forKey: cacheKey) {
            completion(cached as Data, targetWidth, targetHeight)
            return
        }

        let ctx = self.docPtr
        DispatchQueue.global(qos: .userInitiated).async {
            guard pageIndex >= 0 && pageIndex < Int(djvu_doc_page_count(ctx)) else {
                DispatchQueue.main.async { completion(nil, 0, 0) }
                return
            }

            let (dw, dh, _) = self.getPageDimension(pageIndex: pageIndex) ?? (300, 400, 72)
            let w = targetWidth > 0 ? targetWidth : dw
            let h = targetHeight > 0 ? targetHeight : dh

            let byteCount = w * h * 4
            var buffer = [UInt8](repeating: 0, count: byteCount)
            var actualW: UInt32 = 0
            var actualH: UInt32 = 0

            let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return -1 }
                return djvu_doc_render_page_rgba(ctx, UInt32(pageIndex), UInt32(w), UInt32(h), UInt32(layerMode.rawValue), base, &actualW, &actualH)
            }

            guard res == 0, actualW > 0, actualH > 0 else {
                DispatchQueue.main.async { completion(nil, 0, 0) }
                return
            }

            let finalW = Int(actualW)
            let finalH = Int(actualH)
            let data = Data(buffer.prefix(finalW * finalH * 4))
            self.rawDataCache.setObject(data as NSData, forKey: cacheKey)

            DispatchQueue.main.async {
                completion(data, finalW, finalH)
            }
        }
    }

    public func prefetchPages(around centerPage: Int, targetWidth: Int, targetHeight: Int, layerMode: LayerMode) {
        let range = max(0, centerPage - 2)...min(pageCount - 1, centerPage + 2)
        for p in range where p != centerPage {
            renderPage(pageIndex: p, targetWidth: targetWidth, targetHeight: targetHeight, layerMode: layerMode) { _ in }
        }
    }

    public func getBookmarks() -> [BookmarkItem] {
        guard let cStr = djvu_doc_get_bookmarks_json(docPtr) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([BookmarkItem].self, from: data)) ?? []
    }

    public func getTextZones(pageIndex: Int) -> [TextZone] {
        guard let cStr = djvu_doc_get_text_zones_json(docPtr, UInt32(pageIndex)) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TextZone].self, from: data)) ?? []
    }

    public func searchText(query: String) -> [SearchResult] {
        guard let cStr = djvu_doc_search_text_json(docPtr, query) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SearchResult].self, from: data)) ?? []
    }

    public func exportPage(pageIndex: Int, format: Int, outputPath: String) -> Bool {
        let res = djvu_doc_export_page(docPtr, UInt32(pageIndex), UInt32(format), outputPath)
        return res == 0
    }
}
