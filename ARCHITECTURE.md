# DJView Architecture & Technical Specification

DJView is a high-performance, native macOS DjVu document viewer inspired by Apple Preview. It combines a high-speed **Rust core** (`djvu-rs`) for DjVu parsing, decoding, rendering, and text/outline extraction with a native **macOS Swift / SwiftUI / AppKit / Metal** frontend.

---

## 1. System Overview

```
+-----------------------------------------------------------------------+
|                             DJView App                                |
|             (SwiftUI / AppKit / Metal / SF Symbols UI)               |
+-----------------------------------------------------------------------+
|  - Main Window & Split Navigation Sidebar                            |
|  - Continuous Scroll Canvas / Single Page / Dual Page (Manga Mode)     |
|  - Metal MTKView GPU Texture Renderer & Layer Shader Shading Pipeline |
|  - Text Selection & Interactive Annotation Overlay Layer             |
|  - Bookmarks / TOC / OCR Full-Text Search Sidebar View                |
|  - UserDefaults Reading Position & Recent Files State Persistence    |
+-----------------------------------------------------------------------+
                                   |
                         C-FFI / C Header Bridge
                                   |
+-----------------------------------------------------------------------+
|                     djvu-bridge (Rust Core Engine)                    |
+-----------------------------------------------------------------------+
|  - djvu-rs crate (Pure Rust DjVu decoder, rendering, text/hocr)      |
|  - Document Management & Multithreaded Page Rendering                 |
|  - DjVu Layer Extraction (Full Color, Foreground, Background, Mask)   |
|  - Document TOC & OCR Text Indexing & Search Engine                   |
|  - Image / PDF Export Engine                                          |
+-----------------------------------------------------------------------+
```

---

## 2. Component Breakdown

### 2.1 Rust Core Engine (`djvu-bridge`)
- **Document Handle Management**: Thread-safe pointer-based API (`*mut DjVuDocContext`).
- **Page Decoding & Rendering**: Renders pages into RGBA 32-bit pixel buffers at specified DPI/zoom scale.
- **Layer Controls**:
  - `0`: Full Composite Color
  - `1`: Foreground Layer
  - `2`: Background Layer
  - `3`: Mask / B&W Bilevel Layer
- **Text & OCR Engine**:
  - Extracts word-level bounding boxes and text content.
  - Full-text search with match highlighting coordinates.
- **TOC & Bookmarks**:
  - Parses embedded document bookmark tree into JSON structure for Swift UI.
- **Page Exporter**:
  - Exports single pages or full documents to PNG, JPEG, TIFF, or PDF.

### 2.2 Swift / Metal Frontend (`DJView`)
- **Native macOS Interface**:
  - Built with SwiftUI for modern macOS aesthetic (Translucent sidebars, Toolbar items, SF Symbols).
  - High performance continuous scrolling list with lazy rendering & off-screen viewport prefetching.
- **Metal Page Renderer (`MetalRenderer.swift`)**:
  - Low-latency `MTKView` displaying rendered page pixel textures.
  - Metal fragment shaders for hardware color adjustments, high-DPI bilinear filtering, contrast/invert modes, and layer masking.
- **View Modes**:
  - **Single Page / Fit Page / Fit Width / Actual Size / Custom Zoom (10% - 500%)**.
  - **Continuous Vertical Scrolling View**.
  - **Manga Mode**: Right-To-Left dual-page side-by-side reading layout.
- **Interactivity**:
  - **Text Selection & Copying**: Mouse selection box across extracted text bounding boxes with `NSPasteboard` support.
  - **Annotation Engine**: Highlight text, draw ink/rectangles, save/load custom annotations overlay file.
  - **Bookmarks & State**: Automatically persists page index, scroll offset, zoom level, and open document history.

---

## 3. Directory Layout

```
/Users/ricepies/Documents/djview/
├── README.md                  # Project overview & build instructions
├── HANDOVER.md                # Agent session handover notes & status
├── ARCHITECTURE.md            # System architecture (this file)
├── TODO.md                    # Detailed checklist of completed & upcoming tasks
├── scripts/
│   └── build.sh               # One-touch build script for Rust staticlib & Swift app
├── djvu-bridge/               # Rust C FFI static crate
│   ├── Cargo.toml
│   ├── include/
│   │   └── djvu_bridge.h      # C ABI header for Swift bridging
│   └── src/
│       ├── lib.rs             # C FFI C API definitions
│       ├── doc.rs             # Document wrapper & page cache
│       ├── render.rs          # Page rasterization & layer extraction
│       ├── text.rs            # OCR text parsing & search
│       └── export.rs          # Exporting to PNG/JPEG/TIFF/PDF
└── DJView/                    # Swift macOS Native App
    ├── DJView.xcodeproj / Package.swift
    ├── Sources/
    │   ├── App/
    │   ├── Models/
    │   ├── Engine/
    │   ├── Views/
    │   └── Shaders/
    └── Resources/
```
