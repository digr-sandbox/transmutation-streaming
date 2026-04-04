# Installation & Setup Guide

Transmutation is a lightweight, pure Rust application. It requires minimal external dependencies and can be installed via automated scripts or manual compilation.

## 📋 Prerequisites
*   **Rust Toolchain**: Nightly 1.85+ (`rustup toolchain install nightly`).
*   **Tesseract OCR**: Required if you need to extract text from images.
*   **Poppler**: Required if you need to render PDF pages to images.

---

## 🚀 Automated Installation (Recommended)

Transmutation provides dependency installers for all major platforms. These scripts install the necessary build tools and optional runtime dependencies (Tesseract, Poppler).

### Windows
Run in an **Administrator** PowerShell:
```powershell
.\install\install-deps-windows.ps1
```
*Alternatively, use `.\install\install-deps-windows.bat` for winget.*

### Linux (Debian/Ubuntu)
```bash
./install/install-deps-linux.sh
```

### macOS (Homebrew)
```bash
./install/install-deps-macos.sh
```

---

## 🏗️ Building from Source

Once dependencies are installed, clone the repository and build the release binaries:

```bash
# Clone the repository
git clone https://github.com/hivellm/transmutation.git
cd transmutation

# Build with CLI and Office support
cargo build --release --features cli,office
```

The resulting binaries will be in `target/release/`:
*   `transmutation`: The main CLI tool.
*   `transmutation-mcp-proxy`: The MCP gateway for AI agents.

---

## 📦 Windows MSI Installer
If you are on Windows, you can generate a portable MSI installer using the WiX Toolset:

```powershell
.\scripts\build-msi.ps1
```
The installer will be generated at `target/wix/transmutation-x64.msi`.

---

## 🐳 Docker Deployment
For zero-dependency deployment, use the provided Dockerfile:

```bash
# Build the image
docker build -t transmutation .

# Run a conversion
docker run -v $(pwd)/data:/app/data transmutation convert /app/data/doc.pdf
```

---

## 🛠️ Verification
After installation, verify the engine is working:

```bash
# Check version
./target/release/transmutation --version

# Run a sample conversion (if you have a PDF)
./target/release/transmutation convert sample.pdf -o output.md
```
