# DJView Development Checklist & Feature Matrix

## Minimum Excellent DjVu Viewer Requirements
- [x] **Open DjVu**: File picker dialog, drag-and-drop support, command-line opening (`DJView <file.djvu>`).
- [x] **Fast Page Renderer**: Multithreaded Rust `djvu-rs` rendering pipeline with C FFI layer.
- [x] **Continuous Scrolling**: Vertical scrolling canvas with lazy viewport prefetching (`ContinuousScrollView`).
- [x] **Thumbnail Sidebar**: Interactive thumbnail sidebar grid with jump-to-page (`ThumbnailsView`).
- [x] **Zoom / Fit Modes**: Fit Width, Fit Page, Actual Size (100%), and smooth custom zoom (10% - 500%).
- [x] **OCR Search**: Full-text document search with bounding box match highlights on canvas & result list (`SearchSidebarView`).
- [x] **Copy Text**: Mouse drag selection box over OCR text layer with `Cmd+C` clipboard copying.
- [x] **Bookmarks**: Embedded NAVM table of contents outline tree & user custom page bookmarks (`TOCView`).
- [x] **Export Page Image**: Export active page to PNG or JPEG format.
- [x] **Remember Reading Position**: Automatic `UserDefaults` state persistence for page index, zoom level, and layout mode per file.

## Advanced & Power Features
- [x] **Metal Renderer**: Low-latency `MTKView` GPU texture pipeline with Metal custom shaders.
- [x] **Metal Shaders**: Real-time **Invert (Dark Mode)**, **Sepia**, **Grayscale**, and **High Contrast** color filters.
- [x] **Annotations**: Add sticky notes and highlight overlays directly on document pages.
- [x] **Manga Mode**: Right-to-Left dual-page side-by-side reading layout.
- [x] **Layer Controls**: Switch DjVu layers dynamically: **Full Color**, **Foreground**, **Background**, and **Mask / Bilevel**.

## Handover & Build Quality
- [x] **Scoped Workspace**: All edits contained strictly inside `/Users/ricepies/Documents/djview`.
- [x] **Git Repository**: Initialized Git repository.
- [x] **Handover Structure**: `HANDOVER.md`, `ARCHITECTURE.md`, `README.md`, `TODO.md` documentation.
- [x] **Automated Build Script**: `./scripts/build.sh` produces standard macOS `DJView.app` bundle.
