import Foundation
import AppKit
import CoreGraphics
import CDjVuBridge

// MARK: - FFI JSON Decoding Wrappers
private struct RawTextZone: Codable {
    let kind: String
    let text: String
    let x: UInt32
    let y: UInt32
    let width: UInt32
    let height: UInt32
    let children: [RawTextZone]
}

private struct RawSearchResult: Codable {
    let page: Int
    let text: String
    let x: UInt32
    let y: UInt32
    let width: UInt32
    let height: UInt32
}

// MARK: - O(1) LRU Cache Data Structure (Doubly-Linked List + Hash Map)
final class LRUNode<K: Hashable, V> {
    let key: K
    var value: V
    var prev: LRUNode?
    var next: LRUNode?

    init(key: K, value: V) {
        self.key = key
        self.value = value
    }
}

final class LRUCache<K: Hashable, V> {
    private let capacity: Int
    private var map = [K: LRUNode<K, V>]()
    private var head: LRUNode<K, V>?
    private var tail: LRUNode<K, V>?
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: K) -> V? {
        lock.lock()
        defer { lock.unlock() }
        guard let node = map[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func set(_ key: K, _ value: V) {
        lock.lock()
        defer { lock.unlock() }
        if let node = map[key] {
            node.value = value
            moveToHead(node)
        } else {
            let node = LRUNode(key: key, value: value)
            map[key] = node
            addToHead(node)
            if map.count > capacity {
                removeTail()
            }
        }
    }

    private func moveToHead(_ node: LRUNode<K, V>) {
        if node === head { return }
        removeNode(node)
        addToHead(node)
    }

    private func addToHead(_ node: LRUNode<K, V>) {
        node.next = head
        node.prev = nil
        if let h = head {
            h.prev = node
        }
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func removeNode(_ node: LRUNode<K, V>) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }
    }

    private func removeTail() {
        guard let t = tail else { return }
        map.removeValue(forKey: t.key)
        removeNode(t)
    }
}

public final class DjVuEngine {
    public let docPtr: OpaquePointer
    private let pageCache = LRUCache<String, NSImage>(capacity: 20)
    private let rawDataCache = LRUCache<String, Data>(capacity: 20)
    private let renderQueue = DispatchQueue(label: "org.deja.renderQueue", qos: .userInitiated)

    public var pageCount: Int {
        Int(djvu_doc_page_count(docPtr))
    }

    public init?(filePath: String) {
        guard let ctx = djvu_doc_open(filePath) else {
            return nil
        }
        self.docPtr = ctx
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
        let cacheKey = "\(pageIndex)_\(targetWidth)_\(targetHeight)_\(layerMode.rawValue)"
        if let cached = pageCache.get(cacheKey) {
            completion(cached)
            return
        }

        let ctx = self.docPtr
        renderQueue.async {
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
            self.pageCache.set(cacheKey, img)

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
        let cacheKey = "raw_\(pageIndex)_\(targetWidth)_\(targetHeight)_\(layerMode.rawValue)"
        if let cached = rawDataCache.get(cacheKey) {
            completion(cached, targetWidth, targetHeight)
            return
        }

        let ctx = self.docPtr
        renderQueue.async {
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
            self.rawDataCache.set(cacheKey, data)

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

    public func exportPage(pageIndex: Int, format: Int, outputPath: String) -> Bool {
        guard let pathCStr = outputPath.cString(using: .utf8) else { return false }
        let res = djvu_doc_export_page(docPtr, UInt32(pageIndex), UInt32(format), pathCStr)
        return res == 0
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
        if jsonStr == "null" { return [] }
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        guard let rawZones = try? JSONDecoder().decode([RawTextZone].self, from: data) else { return [] }
        return rawZones.map { convertRawTextZone($0) }
    }

    public func searchText(query: String) -> [SearchResult] {
        guard let queryCStr = query.cString(using: .utf8) else { return [] }
        guard let cStr = djvu_doc_search_text_json(docPtr, queryCStr) else { return [] }
        defer { djvu_string_free(cStr) }
        let jsonStr = String(cString: cStr)
        guard let data = jsonStr.data(using: .utf8) else { return [] }
        guard let rawResults = try? JSONDecoder().decode([RawSearchResult].self, from: data) else { return [] }
        return rawResults.map {
            SearchResult(
                page: $0.page,
                text: $0.text,
                rect: CGRect(x: Double($0.x), y: Double($0.y), width: Double($0.width), height: Double($0.height))
            )
        }
    }

    private func convertRawTextZone(_ raw: RawTextZone) -> TextZone {
        TextZone(
            text: raw.text,
            rect: CGRect(x: Double(raw.x), y: Double(raw.y), width: Double(raw.width), height: Double(raw.height)),
            kind: raw.kind,
            children: raw.children.map { convertRawTextZone($0) }
        )
    }
}
