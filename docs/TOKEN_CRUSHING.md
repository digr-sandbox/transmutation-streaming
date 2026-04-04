# Semantic Transmutation: The Token Crushing Pipeline

Transmutation uses a multi-stage pipeline to squeeze massive amounts of data into high-signal Markdown context. Unlike simple truncation, Transmutation uses statistical and structural models to determine what information is critical for an LLM's reasoning.

## 1. Latent-K: Structural Structure Discovery
> [!IMPORTANT]
> Transmutation does **not** use the closed-source commercial Latent-K product. We have engineered our own custom version based on academic research in **Latent Variable Models (LVMs)** and the **Interpolative Convex Rank (ICR)**.

**The Theory**: We treat a source file as a semantic volume. The implementation details are the "bulk," while the dependencies and signatures are the "extreme points" (the convex hull) of the file's meaning.
*   **Application**: By finding the $k$ structural vertices of a file, we can prune 90% of the text while ensuring the LLM understands exactly what the code consumes and what it produces.
*   **Result**: A "Structural Skeleton" that remains 100% syntactically valid but uses 1/50th of the tokens.

## 2. TOON: Token-Oriented Object Notation
For structured formats (JSON, XML, HTML, and Office Docs), statistical pruning would destroy the data. Instead, Transmutation routes these through a native **TOON Squeezer**.

**Mechanism**:
*   **Array Collapsing**: Replaces repetitive JSON arrays with space-delimited value streams.
*   **Hierarchical Flattening**: Converts deep objects into dot-notation dictionaries.
*   **Tag Stripping**: For HTML/XML, it removes all closing tags and simplifies opening tags to attribute lists.

### Pure Rust Office Transmutation
Unlike traditional converters that require LibreOffice or Pandoc, Transmutation achieves **zero-dependency Office conversion**:
1.  **ZIP Extraction**: DOCX, XLSX, and PPTX are unzipped in-memory (or spooled to disk for large files).
2.  **XML Squeezing**: The internal `word/document.xml` or `xl/worksheets/sheet1.xml` is passed directly to the TOON engine.
3.  **Semantic Mapping**:
    *   **DOCX**: Paragraphs and runs are extracted and converted to high-density Markdown.
    *   **XLSX**: Sheets are mapped to TOON dot-notation or Markdown tables, stripping thousands of metadata tags.
    *   **PPTX**: Slides are processed individually, maintaining structural hierarchy while crushing visual "noise."

This approach allows for **700x+ compaction** on standard Word documents by ignoring the megabytes of styling and metadata XML inherent in the OOXML format.

## 3. Statistical Semantic Squeezer
For unstructured logs and shell output, the engine applies a probabilistic model:
*   **IDF Scoring**: Tokens that appear constantly (timestamps, headers) are de-weighted. Tokens that appear rarely (Error IDs, hex codes) are protected.
*   **Local Entropy**: Measuring windowed diversity to prune progress bars and repeating patterns.
*   **U-Shaped Weighting**: Protecting the beginning and end of long streams to mitigate the "Lost-in-the-Middle" effect.

## 🛡️ Grounding & Provenance
To prevent hallucinations, every "crushed" output is wrapped in a **Provenance Header**:

```text
# ⚡ PROVENANCE [ID: req_171224 | Transformed: Latent-K + TOON]
---
... crushed content ...
```

This header serves two roles:
1.  **Grounding**: It signals to the LLM that it is reading a transformed representation, not the raw bytes.
2.  **Recovery**: The `request_id` allows the agent to call `get_provenance(id)` to retrieve the original ground truth from the SQLite audit database if a hallucination is suspected.

## 🧪 Verified Languages & Formats
The Token Crusher has been verified against:
*   **Code**: Rust, TypeScript, Python, C++, Go, SQL, GraphQL.
*   **Structured**: JSON, XML, HTML, DOCX, XLSX, PPTX.
*   **Logs**: Nginx, Cargo, NPM, CMake, Systemd.

## 🧠 LLM Independence
The entire crushing pipeline is written in **Pure Rust**. 
*   **No LLM Calls**: We do not use an LLM to summarize text. All summaries are deterministic and mathematical.
*   **Zero Cost**: Process 100GB of logs locally without spending a single API token.
*   **Zero Latency**: Statistical pruning happens at over 500MB/s on a modern CPU.
