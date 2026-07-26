# DJView — Native macOS DjVu Viewer

**DJView** is a high-performance, native macOS DjVu document viewer inspired by Apple Preview. Built with a pure **Rust core** (`djvu-rs`) and a modern **macOS Swift / SwiftUI / AppKit / Metal** frontend.

---

## Features

- 📄 **Open DjVu Documents**: Seamless opening, drag-and-drop support, recent files tracking.
- ⚡ **Metal GPU Acceleration**: Ultra-fast rendering with custom Metal shaders for **Invert (Dark Mode)**, **Sepia**, **Grayscale**, and **High Contrast**.
- 📜 **Continuous Scrolling View**: Smooth 60/120fps continuous vertical scrolling with lazy rendering.
- 📖 **Manga Mode**: Right-to-Left dual-page side-by-side reading layout.
- 🖼️ **Thumbnail Sidebar**: Instant page previews with click-to-jump navigation.
- 📑 **Table of Contents & Bookmarks**: Parse NAVM outline tree & user custom page bookmarks.
- 🔍 **OCR Search**: Full-text document search with bounding-box match highlighting on rendered pages.
- ✂️ **Text Selection & Copy**: Drag mouse over page text layer to select and copy text (`Cmd+C`).
- 🎨 **Layer Controls**: Switch DjVu layers: **Full Color**, **Foreground**, **Background**, and **Mask/B&W**.
- ✏️ **Annotations**: Add highlights, sticky notes, and drawing shapes directly on pages.
- 💾 **Export Page**: Export pages to **PNG** or **JPEG**.
- 🧠 **Remember Reading Position**: Automatically saves last page, scroll position, and zoom level per document.

---

## Project Architecture

```
/Users/ricepies/Documents/djview/
├── ARCHITECTURE.md           # Deep architectural specification
├── HANDOVER.md               # Agent session handover state & notes
├── README.md                 # Project README (this file)
├── TODO.md                   # Completed features checklist
├── scripts/
│   └── build.sh              # One-click script building Rust & Swift into DJView.app
├── djvu-bridge/              # Rust crate wrapping djvu-rs with C FFI
│   ├── Cargo.toml
│   ├── include/
│   │   └── djvu_bridge.h     # C ABI header
│   └── src/
│       └── lib.rs            # Thread-safe FFI implementation
└── DJView/                   # Native macOS Swift/Metal App
    ├── Package.swift
    └── Sources/
        ├── CDjVuBridge/      # C Bridge modulemap & headers
        └── DJView/           # SwiftUI / AppKit / Metal application
```

---

## Build Instructions

### Prerequisites
- macOS 14.0 or newer
- Xcode 15+ / Swift 5.9+
- Rust 1.75+ / Cargo

### Quick Build & Package
Run the automated build script:
```bash
./scripts/build.sh
```

This will build the Rust static library `libdjvu_bridge.a`, compile the Swift executable, and package `DJView.app` bundle in the project root directory.

Launch the app:
```bash
open DJView.app
```
