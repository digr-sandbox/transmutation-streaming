# Transmutation

**High-performance, zero-trust terminal gateway and token-crushing engine for AI Agents.**

Transmutation is a **pure Rust** gateway designed to sit between your shell and agentic tools (Claude Code, OpenClaw, Gemini-CLI, etc.). It provides a Thompson NFA security firewall to prevent destructive commands and a high-signal "crushing" engine to squeeze massive shell outputs into tiny context-safe packets without losing semantic meaning.

## 🎯 Purpose: The Agentic Gateway

Modern AI agents often "over-read" terminal output, wasting thousands of tokens on repetitive logs and boilerplate noise. Transmutation solves this by:
1.  **Security Firewall**: Intercepting every command through a multi-OS secure router to block destructive actions.
2.  **Context Density**: Crushing 100MB of log data into <10KB of high-signal Markdown using statistical and structural algorithms.
3.  **Zero-Trust Auditing**: Maintaining a persistent SQLite audit trail of every transformation for full provenance recovery.
4.  **LLM Independence**: 100% of processing is local, deterministic Rust. No LLM calls, no token costs, and zero latency during processing.

## 🚀 Quick Start

### 1. Install Dependencies
Transmutation is **Zero-Python** and **Zero-LibreOffice**. You only need Tesseract for OCR.
*   **Windows**: `.\install\install-deps-windows.ps1`
*   **Linux**: `./install/install-deps-linux.sh`
*   **macOS**: `./install/install-deps-macos.sh`

### 2. Build the Gateway
```bash
cargo build --release --features cli
```

### 3. Connect your Agent (MCP)
Add Transmutation to your `claude.json` or `mcp.json`:
```json
{
  "mcpServers": {
    "transmutation": {
      "command": "/absolute/path/to/transmutation-mcp-proxy",
      "args": ["--stdio"]
    }
  }
}
```

## 🛡️ Secure Command Router
Transmutation replaces native shell tools with a secure gateway that adapts to your OS:
- **`execute_secure_command`**: Runs shell tasks (build, test, grep) through a Thompson NFA firewall.
- **Multi-OS Protection**: Blocks `rm -rf` on Linux, `Remove-Item -Recurse` on Windows, and Keychain access on macOS.
- **Real-time Auditing**: Every command is hashed and logged to SQLite with its raw output for provenance.

## ⚡ The Token Crushing Pipeline
The engine uses a 3-way routing logic to maximize signal-to-noise ratio:

1.  **Latent-K Structural Extraction**: For code reads (`cat src/lib.rs`), it extracts the **Architecture Code Map** (Imports/Exports) and the **Structural Skeleton** (Signatures only), crushing implementation "slop" while keeping $k$ extreme semantic points.
2.  **TOON Squeezer**: For JSON/XML/HTML (including DOCX/XLSX), it uses **Token-Oriented Object Notation** to flatten hierarchies and collapse arrays, achieving up to 80% compression.
3.  **Statistical Squeezer**: For logs, it uses IDF scoring and Local Entropy Analysis to prune repetitive boilerplate (timestamps, progress bars) while protecting technical signals (IPs, Error Codes).

📖 **Deep Dives:**
- [Architecture & Workflow](docs/ARCHITECTURE.md)
- [MCP Tool Reference](docs/TOOLS.md)
- [Token Crushing Algorithms (Latent-K & TOON)](docs/TOKEN_CRUSHING.md)
- [Benchmarks & Compaction Stats](docs/BENCHMARKS.md)

## 📋 At a Glance: Compaction Results
*Actual results from v0.3.2 test battery:*

| Format | Input Size | Transmuted Size | Gain |
|--------|------------|-----------------|------|
| **DOCX** | 18,079 B | 25 B | **723x** |
| **XLSX** | 4,192 B | 77 B | **54x** |
| **PPTX** | 998 B | 60 B | **16x** |
| **JSON** | 1.2 MB | 140 KB | **8x** |
| **LOGS** | 100 MB | 12 KB | **10,000x** |

## 🛠️ Architecture Diagram
Transmutation sits between the Agent and the OS. It does not intercept HTTPS or OAuth, making it compatible with all enterprise AI plans where tools like Headroom or Bifrost cannot operate.

```text
[ Agent (Claude Code/Gemini) ]
           │
           ▼ (MCP Protocol)
[   Transmutation Gateway    ] <─── [ SQLite Audit Log ]
           │
           ├─ Security Firewall (Thompson NFA)
           ├─ Token Crusher (Latent-K / TOON)
           ▼
[      Operating System      ] (CMD / PWSH / SH)
```

## 📝 License
MIT License - see [LICENSE](LICENSE) for details.
