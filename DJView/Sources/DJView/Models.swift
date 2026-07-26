import Foundation
import CoreGraphics
import SwiftUI

public enum LayerMode: UInt32, CaseIterable, Identifiable {
    case composite = 0
    case foreground = 1
    case background = 2
    case mask = 3

    public var id: UInt32 { rawValue }

    public var title: String {
        switch self {
        case .composite: return "Full Color"
        case .foreground: return "Foreground"
        case .background: return "Background"
        case .mask: return "Mask (B&W)"
        }
    }

    public var icon: String {
        switch self {
        case .composite: return "paintpalette.fill"
        case .foreground: return "square.2.layers.50.top.filled"
        case .background: return "square.2.layers.50.bottom.filled"
        case .mask: return "circle.lefthalf.filled"
        }
    }
}

public enum ColorShaderMode: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case invert = "Invert (Dark Mode)"
    case sepia = "Sepia"
    case grayscale = "Grayscale"
    case highContrast = "High Contrast"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .normal: return "sun.max.fill"
        case .invert: return "moon.fill"
        case .sepia: return "book.closed.fill"
        case .grayscale: return "circle.righthalf.filled"
        case .highContrast: return "slider.vertical.3"
        }
    }
}

public enum ViewLayoutMode: String, CaseIterable, Identifiable {
    case continuous = "Continuous Scroll"
    case singlePage = "Single Page"
    case manga = "Manga (Dual Page RTL)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .continuous: return "doc.on.doc.fill"
        case .singlePage: return "doc.fill"
        case .manga: return "book.pages.fill"
        }
    }
}

public enum ZoomMode: Equatable {
    case fitWidth
    case fitPage
    case actualSize
    case custom(Double)

    public var title: String {
        switch self {
        case .fitWidth: return "Fit Width"
        case .fitPage: return "Fit Page"
        case .actualSize: return "Actual Size (100%)"
        case .custom(let val): return "\(Int(val * 100))%"
        }
    }
}

public struct BookmarkItem: Identifiable, Codable, Hashable {
    public var id = UUID()
    public let title: String
    public let pageNum: Int?
    public let url: String?
    public let children: [BookmarkItem]?

    enum CodingKeys: String, CodingKey {
        case title
        case pageNum = "page_num"
        case url
        case children
    }
}

public struct TextZone: Identifiable, Codable {
    public var id = UUID()
    public let kind: String
    public let text: String
    public let x: UInt32
    public let y: UInt32
    public let width: UInt32
    public let height: UInt32
    public let children: [TextZone]

    public var rect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    enum CodingKeys: String, CodingKey {
        case kind, text, x, y, width, height, children
    }
}

public struct SearchResult: Identifiable, Codable, Hashable {
    public var id = UUID()
    public let page: Int
    public let text: String
    public let x: UInt32
    public let y: UInt32
    public let width: UInt32
    public let height: UInt32

    public var rect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    enum CodingKeys: String, CodingKey {
        case page, text, x, y, width, height
    }
}

public enum AnnotationKind: String, Codable, CaseIterable {
    case highlight = "Highlight"
    case note = "Sticky Note"
    case rect = "Rectangle"
}

public struct Annotation: Identifiable, Codable, Hashable {
    public var id = UUID()
    public let pageIndex: Int
    public let kind: AnnotationKind
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public var colorHex: String
    public var noteText: String

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct DocumentPosition: Codable {
    public var pageIndex: Int
    public var scrollOffsetY: Double
    public var zoomScale: Double
    public var layoutMode: String
}
