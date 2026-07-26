import Foundation
import AppKit
import CDjVuBridge

public final class DjVuEngine: @unchecked Sendable {
    private var ctx: OpaquePointer?
    private let queue = DispatchQueue(label: "org.djview.engine", qos: .userInitiated, attributes: .concurrent)

    public let filePath: String

    public init?(filePath: String) {
        self.filePath = filePath
        let ptr = djvu_doc_open(filePath)
        guard let validPtr = ptr else { return nil }
        self.ctx = validPtr
    }

    deinit {
        if let validPtr = ctx {
            djvu_doc_free(validPtr)
        }
    }

    public var pageCount: Int {
        guard let ctx = ctx else { return 0 }
        return Int(djvu_doc_page_count(ctx))
    }

    public func getPageDimension(pageIndex: Int) -> (width: Int, height: Int, dpi: Int)? {
        guard let ctx = ctx, pageIndex >= 0, pageIndex < pageCount else { return nil }
        var w: UInt32 = 0
        var h: UInt32 = 0
        var dpi: UInt16 = 0
        let res = djvu_doc_get_page_dimension(ctx, UInt32(pageIndex), &w, &h, &dpi)
        guard res == 0 else { return nil }
        return (Int(w), Int(h), Int(dpi))
    }

    public func renderPage(pageIndex: Int, targetWidth: Int, targetHeight: Int, layerMode: LayerMode = .composite, completion: @escaping (NSImage?) -> Void) {
        queue.async { [weak self] in
            guard let self = self, let ctx = self.ctx else {
                completion(nil)
                return
            }

            let (dw, dh, _) = self.getPageDimension(pageIndex: pageIndex) ?? (300, 400, 72)
            let w = targetWidth > 0 ? targetWidth : dw
            let h = targetHeight > 0 ? targetHeight : dh

            let byteCount = w * h * 4
            var buffer = [UInt8](repeating: 0, count: byteCount)

            let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return -1 }
                return djvu_doc_render_page_rgba(ctx, UInt32(pageIndex), UInt32(w), UInt32(h), layerMode.rawValue, base)
            }

            guard res == 0 else {
                completion(nil)
                return
            }

            let data = Data(buffer)
            guard let provider = CGDataProvider(data: data as CFData) else {
                completion(nil)
                return
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

            guard let cgImage = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) else {
                completion(nil)
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
            DispatchQueue.main.async {
                completion(nsImage)
            }
        }
    }

    public func renderPageRawRGBA(pageIndex: Int, targetWidth: Int, targetHeight: Int, layerMode: LayerMode = .composite, completion: @escaping (Data?, Int, Int) -> Void) {
        queue.async { [weak self] in
            guard let self = self, let ctx = self.ctx else {
                completion(nil, 0, 0)
                return
            }

            let (dw, dh, _) = self.getPageDimension(pageIndex: pageIndex) ?? (300, 400, 72)
            let w = targetWidth > 0 ? targetWidth : dw
            let h = targetHeight > 0 ? targetHeight : dh

            let byteCount = w * h * 4
            var buffer = [UInt8](repeating: 0, count: byteCount)

            let res = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return -1 }
                return djvu_doc_render_page_rgba(ctx, UInt32(pageIndex), UInt32(w), UInt32(h), layerMode.rawValue, base)
            }

            guard res == 0 else {
                completion(nil, 0, 0)
                return
            }

            let data = Data(buffer)
            DispatchQueue.main.async {
                completion(data, w, h)
            }
        }
    }

    public func getBookmarks() -> [BookmarkItem] {
        guard let ctx = ctx else { return [] }
        guard let cStr = djvu_doc_get_bookmarks_json(ctx) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([BookmarkItem].self, from: data)) ?? []
    }

    public func getTextZones(pageIndex: Int) -> [TextZone] {
        guard let ctx = ctx, pageIndex >= 0, pageIndex < pageCount else { return [] }
        guard let cStr = djvu_doc_get_text_zones_json(ctx, UInt32(pageIndex)) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TextZone].self, from: data)) ?? []
    }

    public func searchText(query: String) -> [SearchResult] {
        guard let ctx = ctx, !query.isEmpty else { return [] }
        guard let cStr = djvu_doc_search_text_json(ctx, query) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SearchResult].self, from: data)) ?? []
    }

    public func exportPage(pageIndex: Int, format: Int, outputPath: String) -> Bool {
        guard let ctx = ctx, pageIndex >= 0, pageIndex < pageCount else { return false }
        let res = djvu_doc_export_page(ctx, UInt32(pageIndex), UInt32(format), outputPath)
        return res == 0
    }
}
