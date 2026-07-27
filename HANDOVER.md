# DJView — Agentic Handover & Architecture Document

This document provides a complete technical state, design decisions, FFI safety rules, and roadmap for AI coding agents and human developers maintaining **DJView**.

---

## 1. Executive Summary

- **Project Name**: DJView
- **Target OS**: macOS 14.0 (Sonoma) or newer
- **Core Stack**: Pure Rust (`djvu-rs` + custom C FFI bridge) + Swift 5.9 / SwiftUI / AppKit / Metal GPU
- **Build System**: Bash scripts (`./scripts/build.sh`, `./scripts/create_dmg.sh`) wrapping `cargo` & `swift build`
- **Repository**: [https://github.com/YOUR_USERNAME/djview](https://github.com/YOUR_USERNAME/djview)
- **License**: DJView Strong Copyleft License v1.0 (AGPL v3 + anti-Red Hat loophole clause)

---

## 2. Directory Layout & Module Responsibilities

```
djview/
├── README.md                      # Public project documentation
├── LICENSE                        # DJView Strong Copyleft License v1.0
├── CONTRIBUTING.md                # Contributor guidelines
├── ARCHITECTURE.md                # High-level architecture specification
├── HANDOVER.md                    # Detailed agentic handover & maintenance state (this file)
├── scripts/
│   ├── build.sh                   # Builds Rust staticlib + Swift binary -> DJView.app
│   └── create_dmg.sh              # Packages DJView.app -> DJView.dmg
├── docs/
│   └── screenshots/               # App UI screenshots
├── djvu-bridge/                   # Rust C-FFI static library crate
│   ├── Cargo.toml
│   ├── include/
│   │   └── djvu_bridge.h          # C ABI header file for Swift FFI
│   └── src/
│       └── lib.rs                 # FFI bindings, panic boundaries, zero-copy downscaler
└── DJView/                        # Native macOS Swift app package
    ├── Package.swift
    └── Sources/
        ├── CDjVuBridge/           # C modulemap bridging djvu_bridge.h into Swift
        └── DJView/
            ├── DJViewApp.swift    # App entry point, menu commands, tab manager wiring
            ├── TabManager.swift   # Multi-tab state management
            ├── TabBarView.swift   # Chrome-style tab bar component
            ├── TabbedDocumentView.swift # Root container (Tab bar + active MainView)
            ├── MainView.swift     # Main window layout, toolbar, floating HUD
            ├── AppViewModel.swift # Core ViewModel, page navigation, search, export state
            ├── DjVuEngine.swift   # Thread-safe FFI wrapper, LRU cache, serial queue
            ├── CanvasViews.swift  # Continuous scroll, single page, and manga mode views
            ├── MetalRenderer.swift # Metal GPU rendering pipeline (MTKView delegate)
            ├── MetalPageView.swift # SwiftUI wrapper for Metal MTKView
            ├── SidebarViews.swift # Thumbnails, TOC, Bookmarks, Notes, Search sidebar
            ├── Overlays.swift     # Text selection & annotation drawing overlay
            └── Models.swift       # Data models (SearchResult, TextZone, PageNote, etc.)
```

---

## 3. Core Architectural Rules & Invariants

### 3.1. 4-Pixel Alignment for CoreGraphics & Metal
- **Rule**: For 32-bit RGBA buffers, macOS CoreGraphics and Metal require `bytesPerRow` to align to a 16-byte boundary (`width * 4 % 16 == 0`).
- **Implementation**: Target render widths MUST be rounded down to multiples of 4 pixels:
  ```swift
  let targetW = max(4, (rawWidth / 4) * 4)
  ```
- **Files**: `CanvasViews.swift`, `SidebarViews.swift`.

### 3.2. Event-Driven Metal GPU Rendering (0% Idle Usage)
- **Rule**: Metal views must NOT run a continuous 60/120 FPS render loop when static.
- **Implementation**: Set `isPaused = true` and `enableSetNeedsDisplay = true` on `MTKView`. Trigger `mtkView.needsDisplay = true` ONLY when texture data or color shader state changes.
- **Files**: `MetalRenderer.swift`, `MetalPageView.swift`.

### 3.3. Zero-Allocation FFI Downscaling
- **Rule**: Avoid heap allocation (`Vec<u8>`) or heavy image resizing libraries during page zoom/scroll FFI calls.
- **Implementation**: Swift pre-allocates an `[UInt8]` buffer and passes its raw pointer to Rust via `djvu_doc_render_page_rgba`. Rust downscales using direct strided pixel iteration from native `Pixmap` directly into Swift memory in under **0.1ms**.
- **Files**: `djvu-bridge/src/lib.rs`, `DjVuEngine.swift`.

### 3.4. Serial Single-Flight FFI Queue & LRU Cache
- **Rule**: Prevent thread pool flooding and memory spikes during rapid zoom gestures.
- **Implementation**: FFI calls execute serially on a background `renderQueue`. Rendered RGBA buffers are cached in a thread-safe $O(1)$ `LRUCache<K, V>` (Doubly-Linked List + Hash Map) with capacity 20.
- **Files**: `DjVuEngine.swift`.

### 3.5. Clean Export Progress UI State
- **Rule**: Background export progress must display cleanly in the bottom-center `CanvasFloatingHUD` pill without colliding with controls or leaving orphan status indicators.
- **Implementation**: All 5 export handlers (`pdf`, `cbz`, `epub`, `tiff`, `pngFolder`) reset `isExporting = false`, `isPDFConverting = false`, and `isPDFConversionMinimized = false` upon completion and do NOT trigger intrusive Finder popups.
- **Files**: `AppViewModel.swift`, `MainView.swift`.

---

## 4. Build & Workflow Automation

- **Quick Build**:
  ```bash
  ./scripts/build.sh
  ```
  Compiles `djvu-bridge` static library in `release` mode, compiles Swift binary, packages `DJView.app`, and registers with macOS LaunchServices.

- **Create Standalone DMG**:
  ```bash
  ./scripts/create_dmg.sh
  ```
  Executes `./scripts/build.sh`, stages `DJView.app` and `/Applications` symlink, and generates `DJView.dmg`.

- **Git Workflow**:
  ```bash
  git push -u origin main
  ```

---

## 5. Versioning & Release Naming Conventions

- **Semantic Versioning (SemVer)**: `vMAJOR.MINOR.PATCH` (e.g. `v0.1.0` pre-release, `v1.0.0` stable).
- **Dynamic Version Derivation**:
  - `build.sh` automatically reads `git describe --tags --abbrev=0` for `CFBundleShortVersionString` (defaults to `0.1.0` if untagged).
  - `build.sh` automatically counts git commits (`git rev-list --count HEAD`) for `CFBundleVersion`.
- **Release Tagging Workflow**:
  - Create tag: `git tag -a v0.1.0 -m "Release v0.1.0"`
  - Push tags: `git push origin v0.1.0`
- **Release Artifact Naming**:
  - Unversioned installer: `DJView.dmg`
  - Version-stamped installer: `DJView-v0.1.0.dmg` (generated automatically by `./scripts/create_dmg.sh`).

---

## 6. Roadmap & Future Enhancement Recommendations

1. **Touch Bar Support**: Add page slider and zoom buttons for MacBook Touch Bar.
2. **Advanced Annotation Tools**: Add freehand ink drawing, text highlight colors, and line shape creation tools.
3. **EPUB OCR Refinement**: Expand EPUB e-book export to format multi-column text extracted from DjVu OCR layers.
4. **Localization**: Localize UI strings for Japanese, Chinese, French, and German.
