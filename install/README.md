# Transmutation Installation Guide

Transmutation is a high-performance, pure Rust gateway for AI agents. It is designed to be lightweight and requires minimal system dependencies.

## 📋 Prerequisites

*   **Rust Nightly**: Required for building from source (`rustup toolchain install nightly`).
*   **Tesseract OCR** (Optional): Only needed if you want to extract text from images.
*   **Poppler** (Optional): Only needed if you want to render PDF pages to images.

---

## 🚀 Quick Install (Automated)

Transmutation provides automated dependency installers for all major platforms. These scripts install the necessary build tools and optional runtime dependencies.

### Linux (Debian/Ubuntu)
```bash
chmod +x install/install-deps-linux.sh
./install/install-deps-linux.sh
```

### macOS (Homebrew)
```bash
chmod +x install/install-deps-macos.sh
./install/install-deps-macos.sh
```

### Windows (PowerShell + Chocolatey)
```powershell
.\install\install-deps-windows.ps1
```

---

## 🏗️ Building from Source

Once dependencies are installed, you can build the release binaries:

```bash
# Build with core features
cargo build --release --features cli,office
```

The resulting binaries will be in `target/release/`:
*   `transmutation`: The main CLI tool.
*   `transmutation-mcp-proxy`: The Model Context Protocol (MCP) gateway.

---

## 📋 Feature Matrix (v0.3.2+)

Transmutation achieves **Zero-Python** status for all core document formats.

| Feature | System Dependency | Pure Rust | Feature Flag |
|---------|-------------------|-----------|--------------|
| **PDF → Markdown** | None | ✅ 100% Rust | (Always enabled) |
| **PDF → Images** | Poppler | ❌ | `pdf-to-image` |
| **DOCX → Markdown**| None | ✅ 100% Rust | `office` |
| **XLSX → Markdown**| None | ✅ 100% Rust | `office` |
| **PPTX → Markdown**| None | ✅ 100% Rust | `office` |
| **Image OCR** | Tesseract | ✅ Bindings | `image-ocr` |
| **Archives (ZIP)** | None | ✅ 100% Rust | (Always enabled) |
| **HTML/XML** | None | ✅ 100% Rust | (Always enabled) |

---

## 🛡️ Verification

After installation, verify the tools are available in your path:

```bash
# Check Transmutation
./target/release/transmutation --version

# Check Tesseract (if installed)
tesseract --version

# Check Poppler (if installed)
pdftoppm -v
```

---

## 🐳 Docker Deployment

For a fully isolated, zero-dependency environment, use Docker:

```bash
# Build the image
docker build -t transmutation .

# Run a conversion
docker run -v $(pwd)/data:/app/data transmutation convert /app/data/doc.pdf
```

---

**Last Updated**: April 4, 2026  
**Supported Platforms**: Linux, macOS, Windows
