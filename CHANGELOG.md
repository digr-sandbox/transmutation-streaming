# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.3.2] - 2026-04-04

### Added
- **Agentic Gateway Architecture**: Refined Transmutation as a zero-trust bridge between AI agents and the operating system.
- **Secure Command Router**: Thompson NFA-based security firewall for all shell commands.
- **Multi-OS Protection**: Context-aware security rules for Windows, Linux, and macOS.
- **SQLite Audit & Provenance**: Persistent logging of every tool call, request, and response with a 1GB/500-record rotation policy.
- **MCP Tool Suite**: Native support for `query_recon`, `query_discovery`, `query_impact`, and `get_provenance`.
- **Pure Rust Office Pipeline**: Transitioned DOCX, XLSX, and PPTX to a 100% pure Rust XML-to-TOON pipeline.
- **Magic Byte Sniffing**: Added 8KB stream sniffing to detect formats over shell pipes.

### Removed
- **Zero-Python Enforcement**: Removed all Python bridges, Whisper, and FFmpeg dependencies.
- **Stripped Multimedia**: Removed Audio and Video converters to maintain a minimal system footprint.
- **Image Export Removal**: Stripped the visual conversion pipeline (`Office → PDF → Image`) in favor of higher-signal Markdown transmutation.

### Fixed
- **CI Workflow Alignment**: Resolved GitHub Actions build failures by removing obsolete feature gates.
- **Formatting**: Fixed code style issues across the entire workspace.

---

## [0.3.0] - 2025-12-06

**Performance & Memory Optimization Release**

### Performance
- **Cached Regex Patterns**: All regex patterns now compiled once and cached using `OnceLock`.
- **Pre-allocated Buffers**: String and Vec allocations now use `with_capacity()` to minimize reallocations.
- **Optimized Page Processing**: Fixed O(n²) memory issue in PDF extraction.

---

## [0.1.0] - 2025-10-13

### Added
- **Core PDF Conversion**: Pure Rust PDF to Markdown conversion.
- **DOCX Conversion**: Initial pure Rust Word document parsing.
- **CLI Tool**: Command-line interface for local document conversion.
