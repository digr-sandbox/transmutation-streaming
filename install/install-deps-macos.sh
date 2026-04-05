#!/bin/bash
# Install Transmutation dependencies on macOS - Unix LF enforced
set -e

echo "╔════════════════════════════════════════╗"
echo "║  📦 Transmutation Dependencies        ║"
echo "║     macOS (Homebrew)                  ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Please install it first from https://brew.sh/"
    exit 1
fi

echo "📥 Installing ALL dependencies..."
echo ""

# Core tools
echo "[1/3] Installing build tools..."
brew install cmake pkg-config

# PDF support
echo "[2/3] Installing poppler (PDF processing)..."
brew install poppler

# OCR support
echo "[3/3] Installing Tesseract (OCR for images)..."
brew install tesseract tesseract-lang

echo ""
echo "✅ All dependencies installed!"
echo ""
echo "📊 Installed tools:"
echo "  - Xcode tools: $(xcode-select -p)"
echo "  - pdftoppm: $(pdftoppm -v 2>&1 | head -1)"
echo "  - Tesseract: $(tesseract --version | head -1)"
echo ""
echo "🚀 You can now run:"
echo "   transmutation convert document.pdf --format png"
echo "   transmutation convert document.docx -o output.md"
echo "   transmutation convert image.jpg -o ocr.md        # OCR"
echo ""
