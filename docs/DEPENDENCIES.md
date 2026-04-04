# Dependency Management

## Overview

Transmutation uses a **pure Rust approach** to dependencies whenever possible:

1. **Core functionality** is **100% Pure Rust** (no external dependencies).
2. **Advanced features** (OCR, Layout FFI) can optionally use external tools.
3. **Build-time detection** automatically checks for missing dependencies and provides instructions.

## Dependency Detection

### How It Works

When you compile Transmutation with features that require external tools, the `build.rs` script:

1. ✅ **Checks** if the required tool is available in `PATH`.
2. ⚠️ **Warns** if a dependency is missing (but **does NOT fail** the build).
3. 📖 **Provides** platform-specific installation instructions.

### Example Output

```bash
$ cargo build --features "image-ocr"

   Compiling transmutation v0.3.2
warning: 
╔════════════════════════════════════════════════════════════╗
║  ⚠️  Optional External Dependencies Missing             ║
╚════════════════════════════════════════════════════════════╝

Transmutation will compile, but some features won't work:

  ❌ tesseract (tesseract-ocr): Image → Text (OCR)
     Install: sudo apt-get install tesseract-ocr

📖 For detailed installation instructions:
   https://github.com/hivellm/transmutation/blob/main/install/README.md
```

## Cargo.toml Usage

### Pure Rust (No Dependencies)

```toml
[dependencies]
transmutation = { version = "0.3.2", features = ["office"] }
```

### Feature Matrix (v0.3.2+)

| Feature | External Dependency | Required At |
|---------|---------------------|-------------|
| `pdf` | None (Markdown) | - |
| `office` | None (Markdown) | - |
| `image-ocr` | Tesseract OCR | Runtime |
| `docling-ffi` | C++ build tools | Compile-time |

## Installation Scripts

We provide automated installation scripts for all platforms:

### Linux (Debian/Ubuntu)
```bash
./install/install-deps-linux.sh
```
Installs: `build-essential`, `poppler-utils`, `tesseract-ocr`.

### macOS (Homebrew)
```bash
./install/install-deps-macos.sh
```
Installs: `poppler`, `tesseract`.

### Windows (Chocolatey/winget)
```powershell
.\install\install-deps-windows.ps1
```
Installs: `visualstudio2022buildtools`, `cmake`, `poppler`, `tesseract`.

---

## Zero-Python & Zero-Heavy-Dep Vision
As of v0.3.2, Transmutation has successfully eliminated:
- ❌ **Python**: 100% removed (no bridges, no Whisper CLI).
- ❌ **LibreOffice**: 100% removed (Office parsing is now pure Rust XML).
- ❌ **FFmpeg**: 100% removed (Multimedia is out of scope).

---

**Last Updated**: April 4, 2026  
**See also**: [`install/README.md`](../install/README.md), [`README.md`](../README.md)
