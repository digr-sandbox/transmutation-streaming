#!/bin/bash
# Install Transmutation dependencies on Linux (Debian/Ubuntu) - Unix LF enforced
set -e

echo "╔════════════════════════════════════════╗"
echo "║  📦 Transmutation Dependencies        ║"
echo "║     Linux (Debian/Ubuntu)             ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    SUDO="sudo"
else
    SUDO=""
fi

echo "📥 Installing ALL dependencies..."
echo ""

# Update package list
echo "[1/4] Updating package list..."
$SUDO apt-get update -qq

# Core build tools
echo "[2/4] Installing build essentials..."
$SUDO apt-get install -y build-essential cmake git pkg-config libclang-dev clang

# PDF & Image conversion
echo "[3/4] Installing poppler-utils (PDF processing)..."
$SUDO apt-get install -y poppler-utils

# OCR support
echo "[4/4] Installing Tesseract (OCR for images)..."
$SUDO apt-get install -y tesseract-ocr tesseract-ocr-eng tesseract-ocr-por libleptonica-dev libtesseract-dev

echo ""
echo "✅ All dependencies installed!"
echo ""
echo "📊 Installed tools:"
echo "  - Build tools: gcc, cmake, git, clang"
echo "  - pdftoppm: $(pdftoppm -v 2>&1 | head -1)"
echo "  - Tesseract: $(tesseract --version | head -1)"
echo ""
echo "🚀 You can now run:"
echo "   transmutation convert document.pdf --format png"
echo "   transmutation convert document.docx -o output.md"
echo "   transmutation convert image.jpg -o ocr.md        # OCR"
echo ""
