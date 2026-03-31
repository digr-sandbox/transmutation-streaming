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
2.  **Pass 2 (Execution & Pruning):** 
    Read the file a second time. Armed with the global map, we dynamically apply the POS pruning and U-Shaped weighting line-by-line. Because Pass 1 gave us the total file size, the engine perfectly calculates the "Middle" of the document for U-Shaped weighting without needing a tail-buffer. The optimized output is written directly to the final Markdown buffer.
