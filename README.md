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

Transmutation doesn't just "truncate" text; it performs **Semantic Transmutation** using three integrated layers:

### 1. TOON (Token-Oriented Object Notation)
Structural optimization for data formats. It strips quotes from JSON keys, minifies booleans (`true` -> `!t`), and collapses XML/HTML attributes to their bare identifiers.

### 2. Statistical Pruning (IDF + Entropy)
Mathematical token reduction. It calculates the **Inverse Document Frequency (IDF)** and **Vocabulary Entropy** of every word.
- **Locking**: Critical identifiers (IPs, Paths, Error codes) are "Immune" and never pruned.
- **Squeezing**: Common "filler" verbs (`info`, `attempting`, `checking`) and stopwords are pruned based on a confidence threshold.

### 3. Lexicon Legends (Lossless Aliasing)
For repetitive technical data (like IPs or deep API paths), Transmutation aliases long strings into short 2-character codes (e.g., `@1`, `@2`) and prepends a **Legend** for the agent to decode. This allows 100% data recovery with up to 90% byte savings.

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
