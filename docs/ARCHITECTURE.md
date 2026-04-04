# Transmutation Architecture: The Agentic Gateway

Transmutation is a high-performance terminal gateway designed to sit between an **AI Agent** (e.g., Claude Code, Gemini-CLI) and the **Host Operating System**. Unlike traditional converters that work on local files, Transmutation operates at the process boundary, securing and crushing the data flowing through the terminal.

## 1. The Gateway Model
Transmutation acts as a zero-trust proxy. It intercepts agent requests, evaluates them against security policies, executes them in a secure shell, and transmutes the resulting output before serving it back to the agent.

### Why this model?
*   **Privacy & Security**: Native agentic tools often have blind access to the shell. Transmutation adds a Thompson NFA security layer that blocks destructive commands.
*   **Context Optimization**: Agents are limited by context windows. Transmutation ensures that every token served back to the agent has a high semantic value.
*   **Zero Interference**: Because it sits at the MCP/CLI layer, it does not interfere with the agent's internal communication (HTTPS/OAuth), allowing it to work with managed plans (Claude Pro, Gemini Advanced) where network interceptors fail.

## 2. Technical Workflow

```text
[ Agent Request ]
       │
       ▼
[ Security Router ] ───▶ [ Thompson NFA Evaluation ] ───▶ (BLOCK if malicious)
       │
       ▼
[ Execution Engine ] ──▶ [ OS-Native Shell (PWSH/SH) ]
       │
       ▼
[ Streaming Spooler ] ──▶ [ 8KB Reconstructed Window ] ──▶ [ Temp Buffer ]
       │
       ▼
[ Transmutation Pipeline ]
       │
       ├─ [ Latent-K ] (for Code Reads)
       ├─ [ TOON ]     (for Structured Data)
       └─ [ Statistical ] (for Unstructured Logs)
       │
       ▼
[ MCP Tool Response ] ──▶ [ SQLite Audit Log ]
```

## 3. Core Subsystems

### Stdin Streaming Architecture
Transmutation uses a **Single Reconstructed File** streaming model. When data is piped via the shell (`cat log | transmutation convert -`), the engine:
1.  Sniffs the first **8KB** to detect magic bytes (Format Discovery).
2.  Spools the infinite stream to a temporary disk buffer.
3.  Performs line-by-line or block-level transformation with a constant memory footprint (~8KB).

### Multi-OS Security Router
The gateway detects the host OS (`windows`, `linux`, `macos`) and routes commands to the appropriate security ruleset. This prevents "polyglot" attacks where an agent might try to bypass Linux rules using PowerShell syntax.

### The Transmutation Waterfall (3-Way Routing)
Every output is automatically routed to the most semantic engine:
1.  **TOON Squeezer**: Used for JSON, XML, HTML, and Office (DOCX/XLSX/PPTX) files. It flattens the structure to maximize data density.
2.  **Latent-K Skeleton**: Used for source code. It uses Tree-sitter to extract dependencies and signatures while hiding implementation details.
3.  **Statistical Squeezer**: Used for everything else (logs, terminal output). It uses IDF scoring and local entropy to prune noise.

## 4. Audit & Provenance System
Every transformation is non-destructive. The original, raw output is saved to a local **SQLite Audit Database** (`~/.transmutation/audit.db`).
*   Agents receive a **Provenance Header** with a unique `request_id`.
*   This enables the `get_provenance` tool, allowing agents to "look behind the curtain" if they suspect a hallucination or need precise implementation details.

## 5. Deployment Specs
*   **Language**: 100% Pure Rust (Safe/Concurrent).
*   **Memory**: Constant ~8KB for streaming, <50MB peak for large AST indexing.
*   **Startup**: ~2ms cold start (optimized for high-frequency loops).
*   **Integration**: Model Context Protocol (MCP) over Stdio.
