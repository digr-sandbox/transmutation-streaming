# Latent-K & TOON: The Agentic Context Engine

This document outlines the theoretical foundation and practical implementation of the Transmutation context engine. The engine uses advanced probabilistic models and structural minification to optimize shell output for Large Language Models (LLMs).

## 1. The Theory: Latent-K and Expectation-Maximization
The concept of "Latent-K" in Transmutation is derived from the academic literature on Latent Variable Models (LVMs) and the Interpolative Convex Rank (ICR).

### What are Latent Variables?
In machine learning, a **Latent Variable Model** represents a probability distribution $p(x, z; \theta)$, where $x$ represents observed data and $z$ represents hidden (latent) variables. 
As defined by the Ermon Group at Stanford [1], latent variables allow a model to capture underlying, hidden structures that explain the surface-level observations. For example, in a codebase, the text of a file ($x$) is observed, but the underlying architectural "purpose" or "component" ($z$) is hidden.

### Expectation-Maximization (EM)
To discover these hidden structures, we rely on the Expectation-Maximization algorithm [2]. EM is an iterative method used to find maximum likelihood estimates of parameters in statistical models where the equations cannot be solved directly due to the unobserved variables.
1. **E-Step (Expectation)**: The engine calculates the "responsibilities"—the probability that a specific latent component is responsible for a given token in the code.
2. **M-Step (Maximization)**: The engine updates its belief about what those core components are.

### The Interpolative Convex Rank (ICR)
In a recent paper by Bhattacharyya et al. [3], the problem of finding $k$ (the exact number of extreme points or "pure components" in a latent polytope) was solved using the Interpolative Convex Rank. 

**Application in Transmutation**: 
When an agent reads a massive source code file (`cat src/lib.rs`), Transmutation does not blindly compress the text. It uses the Latent-K concept to find the "extreme points" (the convex hull) of the file's semantics. 
* We bound the context to the $k$ structural vertices: Outbound Dependencies (what the file consumes) and Public Interfaces (what it produces). 
* By keeping only these $k$ extremes, we guarantee the LLM receives the full structural boundaries of the file using the absolute minimum number of tokens, while pruning the dense "volume" (the internal implementation logic).

## 2. TOON: Token-Oriented Object Notation
For highly structured data (JSON, XML, HTML), statistical pruning destroys the syntax. Instead, Transmutation routes these formats through a custom **Native TOON Squeezer**.

While inspired by the TOON format [4], Transmutation implements a robust, dependency-free array flattener directly in the engine to guarantee compatibility and performance. It achieves massive compression by:
* **Flattening Hierarchies**: Deeply nested XML/HTML DOM trees and JSON objects are converted into flattened key-value dictionaries.
* **Array Collapsing**: Instead of repeating keys for every object in a list, the native TOON engine collapses them into array syntax (e.g., `files[14]: a.txt b.txt c.txt`).
* **Tag Stripping**: All structural bloat (quotes around keys, closing XML tags `</div>`, HTML noise like `<!DOCTYPE>`) is stripped, retaining only the relational data.

## 3. The Code Map & Background Indexer
To prevent the agent from blindly guessing file relationships via `grep`, Transmutation maintains a real-time, language-independent dependency graph of the workspace.

### Tree-sitter & Async Notify
1. **Background Watcher**: An async `notify` process watches the workspace for file changes.
2. **Universal Parsing**: When a file is modified, `tree-sitter` (using language-specific grammars for Rust, TypeScript, Python, etc.) parses the Abstract Syntax Tree (AST) to extract imports and exports.
3. **SQLite Graph**: These relationships are saved as edges in the `audit.db` SQLite database.

### The `read_code_map` Tool
Agents are provided a specific MCP tool: `read_code_map`.
* **Input**: `{"filename": "src/components/Button.tsx"}`
* **Output**: A lightning-fast, zero-latency return of what files the target imports, and what files import the target.

## 4. The 3-Way Routing Architecture
When Transmutation proxies a shell command, it dynamically routes the `stdout` to one of three engines:

1. **The TOON Squeezer**: If the payload parses as JSON, XML, or HTML, it is flattened and minified to save tokens while preserving 100% of the data relationships.
2. **The Latent-K Extractor (with Code Map)**: If the command is a Code Read (`cat`, `head`), the engine merges two critical pieces of context:
   * It queries the SQLite graph to attach the **Architecture Code Map** (Imports/Exports).
   * It extracts the $k=1$ structural skeleton (Dependencies + Signatures) and hides the implementation bodies.
3. **The Statistical Squeezer**: For unstructured logs and `grep` searches, it calculates the Inverse Document Frequency (IDF) and Local Entropy to aggressively drop noise while protecting critical technical signals (IPs, Paths, Error Codes).

### Example: Unified Latent-K Output
If an agent runs `cat src/converters/pdf.rs`, Transmutation returns:
```text
# ⚡ PROVENANCE [V: 3.0 | Latent-K Extraction + Code Map]
# Implementation pruned. Call `execute_command_unaltered` for full source.
---
[ARCHITECTURE CODE MAP]
File: src/converters/pdf.rs
Imports From: src/error.rs, src/types.rs
Imported By: src/lib.rs

[PUBLIC INTERFACE]
pub struct PdfConverter { ... }
impl PdfConverter {
    pub fn new() -> Result<Self> ... }
}
```

### The Escape Hatch
Because Transmutation heavily modifies the terminal output, it exposes a Dual MCP Tool architecture. If the agent needs the raw, uncompressed bytes, it must call the fallback tool: `execute_command_unaltered`.

---
### Sources
1. [Stanford CS228 Notes: Latent Variable Models](https://ermongroup.github.io/cs228-notes/learning/latent/)
2. [Towards Data Science: Latent Variables & Expectation-Maximization](https://towardsdatascience.com/latent-variables-expectation-maximization-algorithm-fb15c4e0f32c/)
3. [Latent k-Polytope and Interpolative Convex Rank (MLR Press)](https://proceedings.mlr.press/v139/bhattacharyya21a/bhattacharyya21a.pdf)
4. [Token-Oriented Object Notation (TOON) Documentation](https://github.com/toon-format/toon-rust)