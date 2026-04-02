# Transmutation

**High-performance zero-trust terminal proxy and token-crushing engine for AI Agents.**

Transmutation is a **pure Rust** gateway designed to sit between your shell and agentic tools (Claude Code, OpenClaw, Gemini-CLI, etc.). It provides a security firewall to prevent destructive commands and a high-resolution "crushing" engine to squeeze massive shell outputs into tiny context-safe packets without losing semantic meaning.

## 🎯 Purpose: The Agentic Gateway

Modern AI agents often "over-read" terminal output, wasting thousands of tokens on repetitive build logs, redundant headers, and boilerplate noise. Transmutation solves this by:
1.  **Security**: Intercepting every command through a Thompson NFA regex engine to block `rm -rf /`, secret dumps, or PaaS destruction.
2.  **Context Density**: Crushing 100MB of log data into <10KB of high-signal Markdown using statistical and structural algorithms.
3.  **Zero-Trust Auditing**: Maintaining a persistent SQLite audit trail of every transformation for full provenance recovery.

## 🛡️ Shell Security: Thompson NFA Firewall

Transmutation implements a Thompson NFA-based security firewall that evaluates commands in real-time.
- **Rule Enforcement**: Blocks commands matching forbidden patterns (e.g., `.env` access, `sudo`, `terraform destroy`).
- **Zero Latency**: Pattern matching happens in microseconds before the shell process even spawns.
- **Multi-Tenant Isolation**: Every request is tagged with a unique ID, ensuring agents can only audit their own command history.

## ⚡ Token Crushing: The Semantic Engine

Transmutation doesn't just "truncate" text; it performs **Semantic Transmutation** using several integrated algorithms to squeeze massive shell outputs into context-safe packets. 

📖 **For a deep dive into the underlying mathematics (Expectation-Maximization) and structural array collapsing, read the [Latent-K Architecture Guide](docs/latent-k.md) and the [TOON Format Specification](docs/toon.md).**

### 🛠️ Dual MCP Tool Architecture
Transmutation exposes two distinct Model Context Protocol (MCP) tools to the agent, providing a safety net against over-compression:

1. **`execute_command` (Default)**: The primary tool. It runs the command, applies security gates, and aggressively crushes the output. If the output is compressed, it prepends a `# ⚡ PROVENANCE` header.
2. **`execute_command_unaltered` (Escape Hatch)**: Runs the command and security gates, but completely **bypasses compression**. The agent is instructed to call this fallback tool ONLY if the default tool returns ambiguous, broken, or overly-pruned results.
3. **`read_code_map` (Architecture Index)**: Queries the background SQLite dependency graph to instantly return what files the target imports, and what files import the target.

### 🔌 Connecting the MCP Server
To use the Transmutation Agentic Gateway in your AI tools, you must configure them to launch the `transmutation-mcp-proxy` binary using the `stdio` transport.

**⚠️ CRITICAL**: Do not use `cargo run` in your MCP configuration. Cargo's startup delay will cause the MCP handshake to time out. You must pre-build the release binary and point your agent directly to the executable.

1. **Pre-build the proxy:**
```bash
cargo build --release --features cli
```

2. **Update your Agent Configuration:**
Replace `/absolute/path/to/` with the actual path to your transmutation repository.

**For Claude Code (`claude.json`):**
```json
{
  "mcpServers": {
    "transmutation": {
      "command": "/absolute/path/to/transmutation-streaming/target/release/transmutation-mcp-proxy",
      "args": ["--stdio"]
    }
  }
}
```

**For OpenClaw / Cursor (`mcp.json`):**
*(Note: On Windows, append `.exe` to the command path)*
```json
{
  "mcpServers": {
    "transmutation": {
      "command": "/absolute/path/to/transmutation-streaming/target/release/transmutation-mcp-proxy",
      "args": ["--stdio"]
    }
  }
}
```

### 🧩 Routing & Latent-K Structural Extraction
The engine dynamically routes output based on the command type:
* **Logs & Searches (`cargo build`, `grep`)**: Routed to the statistical **Semantic Squeezer** (IDF, POS, Entropy).
* **Code Reads (`cat`, `head`)**: Routed to **Structural Extraction**. Semantic compression destroys code syntax. Instead, Transmutation heavily crushes the file by pruning all implementation logic (everything inside `{ ... }`) and returning a **Latent-K Dependency Map (k=1)**. It extracts:
  1. Outbound Dependencies (e.g., `use`, `import`).
  2. The Public Interface (`pub fn`, `struct`, `class`).
  *If the agent needs the exact implementation details, it must call `execute_command_unaltered`.*

### 1. IDF Scoring (calculate_idf)
* **How it works:** Inverse Document Frequency. It builds a global frequency map of all tokens in the stream. Words that appear constantly (like INFO, [DEBUG], or timestamp fragments) get a near-zero score. Words that appear rarely (like NullPointerException or 127.0.0.1) get a massive score spike.
* **Maximum Compression Input:** Massive, repetitive server logs (e.g., 100MB of Nginx access logs). It safely drops the boilerplate while keeping the one line where a 500 error occurred.

### 2. POS Heuristics (calculate_pos_importance)
* **How it works:** Part-of-Speech / Stop-word tagging. It blindly penalizes "function words" (the, a, is, was, in, at) that glue sentences together but don't carry technical weight.
* **Maximum Compression Input:** Highly verbose natural language outputs, such as reading an LLM's conversational prompt, READMEs, or heavily commented code.

### 3. Local Entropy Analysis (calculate_local_entropy)
* **How it works:** It uses a sliding window (e.g., 10 words) to measure vocabulary diversity. If the window contains 10 identical characters or repeating patterns (e.g., ........ or loading... loading...), entropy crashes to 0 and the section is pruned.
* **Maximum Compression Input:** CLI outputs with progress bars, loading spinners, or CMake/NPM build logs that spam repetitive status updates.

### 4. Structured Protection (detect_protected_spans)
* **How it works:** A pre-computation pass that identifies rigid syntactical blocks (JSON payloads, absolute file paths, stack traces, base64 strings) and gives them an `f64::INFINITY` score to immune them from the other algorithms.
* **Maximum Compression Input:** It doesn't compress; it protects. It is most effective when parsing structured API responses embedded inside messy server logs.

### 5. U-Shaped Position Weighting
* **How it works:** Applies a mathematical curve that heavily weights tokens at the very beginning (0-10%) and very end (90-100%) of the document, mitigating the LLM "Lost-in-the-Middle" effect.
* **Maximum Compression Input:** Massive context dumps where the user's initial instruction is at the top, the error summary is at the bottom, and the middle is 50,000 lines of irrelevant log context.

## 🤖 Agentic Shell Proxy (Stdin Streaming)

Transmutation features a highly optimized **Single Reconstructed File** streaming architecture designed specifically to sit in the pipeline between a shell and Agentic IDEs/Tools.

You can pipe infinite shell output directly into the transmuter to safely compress it for your agent's context window:

```bash
# Compress massive shell output for an agent
cat massive_build.log | transmutation convert - --optimize-llm > compressed_context.md

# Safely proxy unknown binary formats (auto-routes to correct engine)
cat unknown_file.mp4 | transmutation convert - --output transcript.md
```

**Key Benefits for Agents:**
- **Zero OOM Crashes:** Massive streams are spooled to disk with a constant ~8KB RAM footprint.
- **Data Integrity:** 100% of the stream is faithfully reconstructed before being passed to the format-specific engine.
- **OOM-Safe Text Engine:** The `TxtConverter` reads reconstructed files line-by-line, preventing memory crashes when formatting 10GB+ log files.

## 📊 Benchmark & Test Results

> [!NOTE]  
> *Test results are currently being finalized using the v24 35-case battery. Actual metrics will be populated upon completion of the evaluation suite.*

| Metric | Target | Current Status |
|--------|--------|----------------|
| **Accuracy** | 99% | [IN PROGRESS] |
| **Compaction (Logs)** | 50% | [IN PROGRESS] |
| **Compaction (JSON)** | 30% | [IN PROGRESS] |
| **Security Latency** | <1ms | ✅ ACHIEVED |

## 📋 Supported Formats (General Conversion)

Transmutation also functions as a high-performance document converter:

| Input Format | Output Options | Status | Features |
|-------------|----------------|---------|----------|
| **PDF** | Markdown, Images, JSON | ✅ Production | Fast, Precision, OCR |
| **DOCX** | Markdown, Images, JSON | ✅ Production | Image Extraction |
| **XLSX** | Markdown tables, CSV | ✅ Production | 148 pg/s |
| **PPTX** | Markdown, Images | ✅ Production | Slide-by-Slide |
| **HTML/XML** | Markdown, JSON | ✅ Production | TOON Structural Minification |
| **TXT/CSV** | Markdown, JSON | ✅ Production | OOM-Safe Buffering |
| **Images** | Markdown (OCR) | ✅ Production | Tesseract Integration |
| **Audio/Video**| Markdown (Transcription) | ✅ Production | Whisper Integration |

## 🚀 Installation

### Windows
**MSI Installer (Recommended):**
Download the latest `.msi` from [Releases](https://github.com/hivellm/transmutation/releases) or build locally:
```powershell
.\build-msi.ps1
msiexec /i target\wix\transmutation-x64.msi
```

### Linux
Use the automated dependency installer:
```bash
curl -sSL https://raw.githubusercontent.com/hivellm/transmutation/main/install/install-deps-linux.sh | bash
cargo install --path . --features "cli"
```

### macOS
Ensure Tesseract and FFmpeg are installed via Brew:
```bash
brew install tesseract ffmpeg
cargo install --path . --features "cli"
```

## 📝 License
MIT License - see [LICENSE](LICENSE) for details.

## 🔗 Links
- **GitHub**: https://github.com/hivellm/transmutation
- **HiveLLM Vectorizer**: https://github.com/hivellm/vectorizer
