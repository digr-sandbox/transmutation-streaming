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

### 1. Download or Build
You can download pre-built binaries for your platform:
*   **Windows**: [`transmutation-x64.msi`](https://github.com/hivellm/transmutation/releases/latest) (Installer)
*   **Linux**: [`transmutation-x86_64-musl`](https://github.com/hivellm/transmutation/releases/latest) (Static Binary)
*   **macOS**: [`transmutation-aarch64-apple-darwin`](https://github.com/hivellm/transmutation/releases/latest) (Apple Silicon)

#### Building Your Own Gateway
If you prefer to build from source, run this single command (requires Rust):
```bash
# Clone and build all features (Office, OCR, CLI)
git clone https://github.com/hivellm/transmutation.git && cd transmutation
cargo build --release --features full
```
*(Transmutation is **Zero-Python**. Only Tesseract is required for the optional `image-ocr` feature).*

### 2. Connect your Agent (MCP)
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

## 📈 Token Savings: The Economic Advantage

Transmutation's primary value is **context economy**. Traditional agentic tools scale linearly with the size of your codebase, leading to "context bloat" where the AI spends 80% of its budget just trying to find where to work. 

The Agentic Gateway replaces broad searches and massive file reads with **High-Density Mapping**.

### 📊 Comparative Analysis: Traditional vs. Agentic Workflow

| Project | Workflow | Traditional Tokens | Agentic Tokens | **Savings %** |
| :--- | :--- | :---: | :---: | :---: |
| **Project 1** (Pure Rust) | Debugging (Build Error) | 15,050 | 4,700 | **68.8%** |
| **Project 1** (Pure Rust) | Adding Feature (New Tool) | 20,600 | 6,250 | **69.7%** |
| **Project 2** (Node/Angular) | Debugging (Permissions) | 32,000 | 4,750 | **85.2%** |
| **Project 2** (Node/Angular) | Adding Feature (Pricing Tier) | 32,000 | 750 | **97.7%** |

*Note: Calculations assume ~200 tokens/KB for full reads and ~15 tokens/line for directory listings/greps.*

---

### 🚀 Scenario: Implementing a New Feature
**The Goal**: Add a "Premium" subscription tier to a massive full-stack application (Project 2).

#### 1. Traditional Method (The "Blind Search" Approach)
*   **Step 1**: Run `ls -R` to find models. (Tokens: **15,000**)
*   **Step 2**: Run `grep -r "Subscription"` to find logic. (Tokens: **2,000**)
*   **Step 3**: Read 3 full service files to understand deps. (Tokens: **15,000**)
*   **Total Usage: 32,000 Tokens**

#### 2. Agentic Gateway Method (The "Surgical" Approach)
*   **Step 1: `query_recon`**
    Instead of 1,000 file names, the AI gets a cluster map.
    *   **Agentic Output**: `[RECON] backend/models: [5 files], frontend/guards: [3 files]`. (Tokens: **100**)
*   **Step 2: `query_discovery <file>`**
    Instead of the whole 2,000-line service, the AI gets the **Structural Skeleton**.
    *   **Agentic Output**: `pub struct Tier { ... }`, `fn validate_access() { ... }`. (Tokens: **500**)
*   **Step 3: `query_impact Tier`**
    Instead of grepping, the AI gets a verified list of every file that imports the `Tier` symbol.
    *   **Agentic Output**: `[IMPACT] Affected: auth.service.ts, payment.controller.ts`. (Tokens: **150**)
*   **Total Usage: 750 Tokens**

---

### 🛠️ Tool Comparison: Signal vs. Noise

| Gateway Tool | Agentic High-Density Output | Traditional "Slop" Alternative |
| :--- | :--- | :--- |
| **`query_recon`** | `[RECON] - src/engines: [12 files]` | 500 lines of `ls -R` recursion. |
| **`query_discovery`**| `fn convert() { ... }` (Signatures only) | 1,000 lines of `cat` implementation logic. |
| **`query_impact`** | `[IMPACT] Used in: lib.rs, main.rs` | 200 noisy `grep` hits in comments and logs. |
| **`query_toon`** | `data.users[849].email: "admin@local"` | 5,000 lines of raw, unparseable `grep` JSON chunks. |

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
