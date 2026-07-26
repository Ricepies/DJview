import Foundation
import CoreGraphics

public struct DocumentPosition: Codable {
    public var pageIndex: Int
    public var scrollOffsetY: Double
    public var zoomScale: Double
    public var layoutMode: String

    public init(pageIndex: Int, scrollOffsetY: Double, zoomScale: Double, layoutMode: String) {
        self.pageIndex = pageIndex
        self.scrollOffsetY = scrollOffsetY
        self.zoomScale = zoomScale
        self.layoutMode = layoutMode
    }
}

public struct UserBookmark: Identifiable, Codable, Equatable {
    public var id: UUID
    public var pageIndex: Int
    public var title: String
    public var createdAt: Date

    public init(id: UUID = UUID(), pageIndex: Int, title: String, createdAt: Date = Date()) {
        self.id = id
        self.pageIndex = pageIndex
        self.title = title
        self.createdAt = createdAt
    }
}

public struct PageNote: Identifiable, Codable, Equatable {
    public var id: UUID
    public var pageIndex: Int
    public var title: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), pageIndex: Int, title: String = "", content: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.pageIndex = pageIndex
        self.title = title.isEmpty ? "Page \(pageIndex + 1) Note" : title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AnnotationKind: String, Codable {
    case highlight = "Highlight"
    case note = "Note"
    case box = "Box"
}

public struct Annotation: Identifiable, Codable, Equatable {
    public var id: UUID
    public var pageIndex: Int
    public var kind: AnnotationKind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var colorHex: String
    public var noteText: String

    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        kind: AnnotationKind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        colorHex: String = "#FFEB3B",
        noteText: String = ""
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colorHex = colorHex
        self.noteText = noteText
    }
}

public struct BookmarkItem: Identifiable, Hashable, Codable {
    public var id: UUID
    public let title: String
    public let pageNum: Int?
    public let children: [BookmarkItem]?

    public init(id: UUID = UUID(), title: String, pageNum: Int?, children: [BookmarkItem]? = nil) {
        self.id = id
        self.title = title
        self.pageNum = pageNum
        self.children = children
    }
}

public struct TextZone: Identifiable, Hashable, Codable {
    public var id: UUID
    public let text: String
    public let rect: CGRect
    public let kind: String
    public let children: [TextZone]

    public init(id: UUID = UUID(), text: String, rect: CGRect, kind: String, children: [TextZone] = []) {
        self.id = id
        self.text = text
        self.rect = rect
        self.kind = kind
        self.children = children
    }
}

public struct SearchResult: Identifiable, Hashable, Codable {
    public var id: UUID
    public let page: Int
    public let text: String
    public let rect: CGRect

    public init(id: UUID = UUID(), page: Int, text: String, rect: CGRect) {
        self.id = id
        self.page = page
        self.text = text
        self.rect = rect
    }
}

public enum LayerMode: Int, CaseIterable, Identifiable {
    case composite = 0
    case background = 1
    case foreground = 2
    case mask = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .composite: return "Full Color"
        case .background: return "Background Layer"
        case .foreground: return "Foreground Layer"
        case .mask: return "B&W Text Mask"
        }
    }

    public var icon: String {
        switch self {
        case .composite: return "photo.on.rectangle"
        case .background: return "photo"
        case .foreground: return "paintpalette"
        case .mask: return "doc.text"
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
        case .normal: return "sun.max"
        case .invert: return "moon.stars"
        case .sepia: return "book"
        case .grayscale: return "circle.righthalf.filled"
        case .highContrast: return "slider.vertical.3"
        }
    }
}

public enum ViewLayoutMode: String, CaseIterable, Identifiable {
    case continuous = "Continuous Scroll"
    case singlePage = "Single Page"
    case manga = "Manga Mode (Dual Right-to-Left)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .continuous: return "scroll"
        case .singlePage: return "doc"
        case .manga: return "book.closed"
        }
    }
}

public enum ZoomMode: Equatable {
    case fitWidth
    case fitPage
    case custom(Double)
}
