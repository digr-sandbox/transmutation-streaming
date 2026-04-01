# Transmutation Integration Roadmap

## 1. Infrastructure Hardening (Completed)
The streaming pipeline has been hardened to prevent OOM crashes during the reconnaissance phase.

### Features implemented:
*   **OOM-Safe Format Detection**: Patched `detect_by_magic_bytes` to read only the first 8KB of a file. This ensures that even if a 100GB stream is spooled to disk, the "Sniffing" phase uses constant RAM.
*   **Feature-Aware Routing**: Improved error messaging to distinguish between truly unsupported formats and recognized formats that are simply missing a feature flag (e.g., `audio`, `video`, `office`).
*   **Binary Stream Stress Tests**: Verified that the "Stream Sniffer" correctly overrides extensions based on magic bytes for PDF, ZIP, and MP3 streams up to 30MB.

## 2. Prompt Compression Engine Integration
We need to integrate the core features of the `compression-prompt` crate into the `transmutation` streaming pipeline to perform on-the-fly context reduction for LLM agents.

### Features to Port:
*   **IDF Scoring (`calculate_idf`)**: Integrate Inverse Document Frequency logic to rank token importance within the streamed chunks.
*   **POS Heuristics (`calculate_pos_importance`)**: Apply multilingual stop-word heuristics to prune low-value "function words" while the stream is being processed.
*   **Local Entropy Analysis (`calculate_local_entropy`)**: Analyze vocabulary diversity in real-time to identify and protect high-information zones in the shell output.
*   **Structured Protection (`detect_protected_spans`)**: Ensure JSON blocks, file paths, and code outputs from the shell are locked and bypass the compression filters.
*   **U-Shaped Position Weighting**: Apply higher importance to the beginning and end of the aggregated output stream to mitigate the *Lost-in-the-Middle* effect for the downstream agent.

### Implementation Strategy: The Two-Pass Architecture
Thanks to the "Single Reconstructed File" spooler in the CLI, the engine has access to the complete document on disk before conversion begins. To maintain our strict OOM-safety guarantees (avoiding loading massive files entirely into RAM) while still achieving perfect global context for the heuristics, we will use a Two-Pass approach inside `TxtConverter`:

1.  **Pass 1 (Global Analysis):** 
    Read the reconstructed file line-by-line via `BufReader` strictly to build the Global Frequency Dictionary (IDF), map vocabulary diversity (Entropy), and index protected spans (JSON/Code blocks). Memory stays flat because we only store mathematical metadata and byte offsets, not the text itself.
3. Finalized Pruning Evaluation (CURRENT)
- [IN PROGRESS] Finalize the **v24 Pruning Suite** breakdown (35 cases).
- [IN PROGRESS] Achieve 99% accuracy across all technical categories (Build Logs, SQL, Git).
- [TODO] Implement the **ROI Profitability Gate**: Only apply compression if net context savings exceed the provenance header overhead.
- [TODO] Validate 50%+ compaction on repetitive server logs via **Lexicon Aliasing**.

## 4. Feature Expansion & Tooling
- [TODO] Analyze the feasibility of including specialized MCP tools to explicitly convert PDF, DOCX, PPTX, XLSX, and other document formats.
- [TODO] Analyze the feasibility of exposing dedicated tools for **PDF-to-Image** rendering and **OCR** (Tesseract) within the Agentic Gateway.

