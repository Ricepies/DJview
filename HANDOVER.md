# DJView Agent Session Handover Document

## 1. Project Context & Status

- **Status**: **COMPLETE & FULLY VERIFIED**.
- **Location**: `/Users/ricepies/Documents/djview`
- **Application**: **DJView** (Native macOS Preview-like DjVu viewer built with Swift, SwiftUI, AppKit, Metal, and Rust `djvu-rs`).

---

## 2. Key Artifacts & Directories

- `DJView.app`: Pre-packaged macOS Application Bundle (run `open DJView.app`).
- `scripts/build.sh`: Automated shell script to build Rust `libdjvu_bridge.a` static library, Swift `DJView` executable, and bundle `DJView.app`.
- `djvu-bridge/`: Rust C FFI library wrapping `djvu-rs` (0.27.0).
  - `src/lib.rs`: FFI exported functions (`djvu_doc_open`, `djvu_doc_render_page_rgba`, `djvu_doc_get_bookmarks_json`, `djvu_doc_search_text_json`, `djvu_doc_export_page`).
  - `include/djvu_bridge.h`: C header for Swift interop.
- `DJView/`: Native Swift macOS Application.
  - `Sources/CDjVuBridge/`: C module map and header.
  - `Sources/DJView/Models.swift`: Data structures.
  - `Sources/DJView/DjVuEngine.swift`: Safe Swift interface calling C FFI.
  - `Sources/DJView/MetalRenderer.swift`: Metal GPU shader pipeline.
  - `Sources/DJView/MetalPageView.swift`: `NSViewRepresentable` MTKView.
  - `Sources/DJView/AppViewModel.swift`: State management, search, persistence.
  - `Sources/DJView/CanvasViews.swift`: Continuous scroll, single page, manga layout views.
  - `Sources/DJView/SidebarViews.swift`: Thumbnails grid, TOC outline, OCR Search, Annotations.
  - `Sources/DJView/Overlays.swift`: Text selection box & annotation drawing layers.
  - `Sources/DJView/MainView.swift`: macOS split view layout & toolbar.

---

## 3. Verification Commands for Subsequent Agents

Any agent resuming this codebase can verify the complete build and test suite with zero human intervention:

```bash
# 1. Test Rust FFI Crate & Unit Tests
cd /Users/ricepies/Documents/djview/djvu-bridge
cargo test

# 2. Build & Package DJView.app
cd /Users/ricepies/Documents/djview
./scripts/build.sh

# 3. Test launch DJView.app
open DJView.app
```

---

## 4. Git History & State

All changes have been committed cleanly to Git in `/Users/ricepies/Documents/djview`.
