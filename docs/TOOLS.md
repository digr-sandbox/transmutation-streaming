# Transmutation MCP Tool Reference

Transmutation provides a specialized set of Model Context Protocol (MCP) tools designed to maximize high-signal context while minimizing token waste.

## 🛠️ Tool Usage Protocol

To maximize efficiency, agents should follow this "Discovery-First" protocol:

1.  **`query_recon`**: Call first to understand the global architectural clusters of the project.
2.  **`query_discovery`**: Call before reading a specific file. It provides the **Architecture Code Map** and **Structural Skeleton**.
3.  **`query_impact`**: Call before modifying a symbol to see the "blast radius" of the change across the workspace.
4.  **`execute_secure_command`**: Use for all shell execution (build, test, grep).
5.  **`get_provenance`**: Call if a hallucination is suspected to retrieve the raw, uncrushed output of a previous command.

---

## 1. `query_recon`
**Purpose**: High-level architectural mapping.
*   **Inputs**: None.
*   **Outputs**: A hierarchical Markdown list of the project's logical clusters (e.g., `ML Logic`, `FFI Layer`, `CLI Entrypoints`).
*   **Token Savings**: Prevents the agent from recursively running `ls -R` or `tree`, saving thousands of tokens in deep directory structures.

## 2. `query_discovery`
**Purpose**: Near-neighbor structural summary of a file.
*   **Inputs**: `path` (string) - Path to the file.
*   **Outputs**: 
    1.  **Architecture Code Map**: List of files that import the target and files the target imports.
    2.  **Structural Skeleton**: All public interfaces, structs, traits, and function signatures. Implementation bodies are crushed to `{ ... }`.
*   **Token Savings**: Typically **10x to 50x** reduction for source files.
*   **Hallucination Protection**: Grounded in real Tree-sitter AST data.

## 3. `query_impact`
**Purpose**: Blast-radius analysis.
*   **Inputs**: `symbol` (string) - The name of a Struct, Trait, or Function.
*   **Outputs**: A list of all files and line numbers where that symbol is used or referenced across the entire workspace.
*   **Token Savings**: Replaces multiple expensive `grep` calls with a single indexed query.

## 4. `execute_secure_command`
**Purpose**: The zero-trust gateway for shell execution.
*   **Inputs**: `command` (string) - The shell command to run.
*   **Outputs**: The **raw** output of the command (Transmutation separates execution from crushing for this tool to ensure implementation details are available when explicitly requested).
*   **Security**: Every command is evaluated by the Thompson NFA multi-OS router.
    *   **Linux**: Blocks `rm -rf`, `sudo`, `.env` access.
    *   **Windows**: Blocks `Remove-Item`, Registry edits (`HKLM:`), and malicious `powershell` string replacements.
    *   **macOS**: Blocks Keychain access and sensitive library paths.

## 5. `get_provenance`
**Purpose**: Verification and hallucination recovery.
*   **Inputs**: `request_id` (string) - The ID found in the `# ⚡ PROVENANCE` header of any crushed output.
*   **Outputs**: A JSON object containing:
    *   The **Raw Input** (the bytes before crushing).
    *   The **Raw Shell Output** (for proxied commands).
    *   Detailed **Statistics** (compaction ratio, algorithms used, timing).
*   **Why use it?**: If an agent is confused by a crushed log or believes a file content was pruned too aggressively, `get_provenance` provides the absolute ground truth from the SQLite audit database.

---

## At a Glance: Savings Summary

| Tool | Native Alternative | Signal Gain | Token Savings |
|------|--------------------|-------------|---------------|
| `query_recon` | `ls -R` / `tree` | **High** (Clusters vs Files) | 90% |
| `query_discovery` | `cat` | **Extreme** (Structure vs Slop) | 95% |
| `query_impact` | `grep -r` | **High** (Verified Refs vs Text) | 80% |
| `execute_secure_command` | `run_shell_command` | **Security** (Verified vs Blind) | N/A |
| `get_provenance` | N/A | **Trust** (Truth vs Pruning) | N/A |
