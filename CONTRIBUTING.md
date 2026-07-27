# Contributing to DJView

Thank you for your interest in contributing! DJView is a two-layer project — a Rust core and a Swift frontend — so contributions can target either layer independently.

---

## Project Layout

```
djview/
├── djvu-bridge/    # Rust crate — DjVu decode, render, FFI
└── DJView/         # Swift macOS app — UI, Metal rendering, tab system
```

---

## Getting Started

1. **Fork** the repository and clone your fork.
2. Install prerequisites:
   - macOS 14+ with Xcode 15 CLT (`xcode-select --install`)
   - Rust 1.75+ (`rustup update`)
3. Build:
   ```bash
   ./scripts/build.sh
   open DJView.app
   ```

---

## What to Work On

Check the open [Issues](https://github.com/YOUR_USERNAME/djview/issues) for good first tasks. Common areas:

- **Rust (`djvu-bridge/src/`)** — decode correctness, render performance, new FFI functions
- **Swift UI (`DJView/Sources/DJView/`)** — new views, sidebar panels, accessibility
- **Metal shaders** — new color filters, rendering effects
- **Export formats** — new output targets (MOBI, DOCX, etc.)

---

## Code Style

**Rust**: `cargo fmt` + `cargo clippy --deny warnings` before committing.

**Swift**: Match surrounding code style. No third-party packages — standard library and Apple frameworks only.

---

## Submitting a Pull Request

1. Create a feature branch: `git checkout -b feat/my-feature`
2. Make focused, surgical changes — one concern per PR.
3. Run the build: `./scripts/build.sh`
4. Open a PR with a clear description of *what* and *why*.

---

## Reporting Bugs

Open an [Issue](https://github.com/YOUR_USERNAME/djview/issues/new) with:
- macOS version
- Steps to reproduce
- A sample `.djvu` file if the bug is document-specific (attach or link a public one)
