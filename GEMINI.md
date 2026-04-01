# GEMINI.md - Project Context & Instructions

## Project Overview
**Transmutation** is a high-performance document conversion engine written in **pure Rust**. It is designed as a lightweight, extremely fast (up to 98x faster than Docling) alternative for transforming various file formats into LLM-friendly outputs (Markdown, JSON, Images).

- **Core Mission**: High-speed document ingestion for AI/LLM embeddings and RAG systems.
- **Key Features**: 27+ formats supported, zero Python dependencies, streaming architecture (constant memory footprint), and optimized for Agentic IDE pipelines.
- **Main Technologies**: Rust 2024 (Nightly), Tokio (Async), Serde, Tesseract (OCR), Whisper (Audio), FFmpeg (Video).

## Building and Running

### Prerequisites
- **Rust Toolchain**: Nightly 1.85+ (`rustup toolchain install nightly`)
- **System Dependencies**: Some features require external tools (Tesseract, Poppler, LibreOffice, FFmpeg, Whisper). Use scripts in `install/` to set them up.

### Key Commands
- **Build**: `cargo build --release` (standard) or `cargo build --features full` (all features).
- **Run CLI**: `cargo run -- convert <input_file> -o <output_file> [options]`
- **Test**: 
  - `cargo test` (Fast tests only, ≤ 20s).
  - `cargo test --features slow` (Includes long-running tests).
  - `cargo test --features s2s` (Includes Server-to-Server integration tests).
- **Quality Checks**:
  - `cargo fmt --all` (Formatting).
  - `cargo clippy --workspace --all-targets --all-features -- -D warnings` (Linting).
  - `cargo llvm-cov --all` (Coverage - **95%+ required**).
- **Windows Installer**: `.\scripts\build-msi.ps1` (Requires WiX Toolset).

## Development Conventions

### 1. Task-Driven Development (Rulebook)
**MANDATORY**: All new features and breaking changes MUST be managed via the `rulebook` CLI.
- **Create Task**: `rulebook task create <task-id>` (must use kebab-case).
- **Structure**: Every task requires a `proposal.md` (Why/What), `tasks.md` (Checklist), and `specs/<module>/spec.md` (Technical requirements using SHALL/MUST).
- **Validation**: Run `rulebook task validate <task-id>` before implementing.
- **Archive**: `rulebook task archive <task-id>` only after 100% completion and tests passing.

### 2. Code Quality & Standards
- **Lints**: All Clippy warnings are treated as errors. See `Cargo.toml` for specific workspace lints.
- **Git Hooks**: Pre-commit and pre-push hooks block any code with lint, test, or type-check errors. **Do not bypass with `--no-verify`.**
- **Async**: Use `tokio` best practices. Never block the async executor; use `spawn_blocking` for CPU-heavy tasks.
- **Error Handling**: Use `thiserror` for library errors and `anyhow` for CLI/application errors. Avoid `unwrap()`/`expect()`.

### 3. Testing Philosophy
- **Fast Tests**: Must complete in < 20 seconds.
- **Slow/S2S Tests**: Must be isolated behind feature flags (`slow`, `s2s`).
- **Coverage**: 95% threshold is strictly enforced.

### 4. File Management
- **Scripts**: All scripts must reside in `/scripts`.
- **Cleanup**: Temporary files must be created in `/scripts` and **deleted immediately** after use.
- **No Deletions**: Never use `rm -rf` in the repo; use proper git commands.

## Project Structure
- `src/bin/`: Main CLI binaries (`transmutation`, `mcp_proxy`).
- `src/converters/`: Format-specific conversion logic (PDF, DOCX, etc.).
- `src/engines/`: Integration with external engines (Docling FFI, Tesseract).
- `src/ml/`: Machine learning models and preprocessing (ONNX).
- `rulebook/`: Project rules, task management, and specifications.
- `docs/`: Comprehensive architecture, setup, and CLI guides.
- `tests/`: Integration tests.
- `examples/`: Usage examples for library and CLI features.

## AI Assistant Role
As an AI agent in this repository, you are a **Senior Rust Engineer**.
1. **Research First**: Check `rulebook/` and `docs/` before proposing changes.
2. **Task First**: Always create a `rulebook` task before implementing a new feature.
3. **Quality Always**: Ensure 95% test coverage and zero clippy warnings.
4. **Follow the Rulebook**: Instructions in `/rulebook/RULEBOOK.md` and `AGENTS.md` take absolute precedence.
