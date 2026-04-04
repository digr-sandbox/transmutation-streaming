#!/bin/bash
# Unified build script for Linux and macOS
# Builds both FFI libraries and the Rust binary

set -e

echo -e "\033[1;36m========================================"
echo -e " Transmutation Unified Build"
echo -e "========================================\033[0m"

# 1. Build C++ FFI Library
if [[ "$*" == *"--ffi"* ]]; then
    echo -e "\n\033[1;33mStep 1: Building C++ FFI libraries...\033[0m"
    ./scripts/build_cpp.sh
else
    echo -e "\n\033[1;33mStep 1: Skipping C++ FFI build (use --ffi to enable)\033[0m"
fi

# 2. Build Rust Binary
echo -e "\n\033[1;33mStep 2: Building Rust binary...\033[0m"
FEATURES="cli,office"
if [[ "$*" == *"--ffi"* ]]; then
    FEATURES="$FEATURES,docling-ffi"
fi

echo -e "Features: $FEATURES"
cargo build --release --features "$FEATURES"

echo -e "\n\033[1;32m========================================"
echo -e " ✅ Build complete!"
echo -e "========================================\033[0m"

# OS specific instructions
if [ "$(uname)" == "Darwin" ]; then
    echo -e "Run with: ./target/release/transmutation --help"
else
    echo -e "Run with: LD_LIBRARY_PATH=\$PWD/libs:\$LD_LIBRARY_PATH ./target/release/transmutation --help"
fi
