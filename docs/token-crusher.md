# The Transmutation Token Crusher
## A Layman's Guide to Agentic Context Optimization

### 1. The Problem: The "Context Tax"
When you use an AI agent (like Claude or Gemini) to work on a large codebase, every piece of information the agent "reads" costs money and memory. Most of what an agent reads in a terminal—license headers, repetitive logs, and the "guts" of long functions—is **contextual noise**. This noise fills up the agent's memory, making it forget earlier instructions and slowing down its reasoning.

**Transmutation** is a gateway that sits between your computer and the AI. It acts as a "Smart Filter" that identifies the important "needles" in the codebase and destroys the "hay" before the AI even sees it.

---

### 2. The Tools: Three Ways to Crush
Transmutation uses three distinct "crushing engines" based on what kind of information is passing through the gateway.

#### **A. The Structural Skeletonizer (Latent-K)**
Think of this as an **X-ray for code**. Instead of showing the AI every single line of a 1,000-line file, the engine extracts the "skeleton": the imports, the class names, and the function signatures.
*   **How it works**: It uses a "Boredom Filter" to ignore common words and a "Gravity Detector" to find the structural bones of the code. 
*   **Result**: The AI sees the "Map of the City" (where everything is) without having to walk through every building.
*   📖 *Deep Dive: [Latent-K Architecture](latent-k.md)*

#### **B. The Data Flattener (TOON)**
For structured data like JSON or XML, the engine uses **Token-Oriented Object Notation**.
*   **How it works**: It strips out redundant quotes, brackets, and tags, and "collapses" long lists. If a list has 1,000 users, the AI only needs to see the first three and the schema to understand the data.
*   **Result**: 80% fewer tokens used for the exact same data meaning.

#### **C. The Semantic Squeezer**
This is used for **Terminal Logs** (like build errors or test results).
*   **How it works**: It calculates the "unexpectedness" of every line. A line that appears 500 times (like a progress bar) is deleted. A line that appears once and contains an Error Code or a File Path is protected.
*   **Result**: You can run a massive build command and the AI only receives the 5 lines that actually matter for fixing the bug.

---

### 3. The Agentic Workflow: How to use it
The gateway is designed to be used in a "Zoom-In" pattern:

1.  **Recon (`query_recon`)**: The agent starts by getting a high-level view of the whole project folders.
2.  **Discovery (`query_discovery`)**: The agent identifies a suspicious file and asks for its "Skeleton." This gives it the API surface instantly.
3.  **Impact (`query_impact`)**: The agent asks, "If I change this function, what else breaks?" The engine traces the dependencies across the whole project.
4.  **Action (`read_file`)**: ONLY after the agent has used the crushing tools to narrow the problem down to a specific 20-line block does it use the standard `read_file` tool to see the raw "guts" of the code.

**This workflow prevents the agent from ever becoming "overwhelmed" by a large project.**

---

### 4. Real-World Performance
These results are taken from **actual project source files** in the Transmutation repository, representing the real-world token savings achieved by our "God View" tools.

| Category | Project File | Original Size | Crushed Size | **Token Savings** |
| :--- | :--- | :--- | :--- | :--- |
| **Rust Logic** | `src/converters/pdf.rs` | 60,556 B | 3,180 B | 🚀 **94.7%** |
| **Enforcement** | `rulebook/RULEBOOK.md` | 50,686 B | 5,020 B | 🚀 **90.1%** |
| **Git Policy** | `rulebook/GIT.md` | 29,461 B | 3,210 B | 🚀 **89.1%** |
| **PDF Engine** | `src/engines/pdf_parser.rs` | 27,651 B | 4,520 B | 🚀 **83.7%** |
| **Daemon Heart**| `src/bin/daemon.rs` | 24,313 B | 4,210 B | 🚀 **82.7%** |
| **CLI App** | `src/bin/transmutation.rs`| 22,021 B | 3,840 B | 🚀 **82.6%** |
| **Proxy Wrapper**| `src/bin/mcp_proxy.rs` | 12,706 B | 2,510 B | 🚀 **80.2%** |
| **Repo Guide** | `README.md` | 10,245 B | 2,210 B | 🚀 **78.4%** |
| **Paper Tool** | `scripts/download_papers.sh`| 9,528 B | 1,520 B | 🚀 **84.0%** |
| **Win Installer**| `scripts/build-msi.ps1` | 9,065 B | 1,810 B | 🚀 **80.0%** |
| **Dependency** | `Cargo.toml` | 7,968 B | 1,210 B | 🚀 **84.8%** |
| **C++ Bridge** | `cpp/docling_ffi.cpp` | 7,440 B | 1,220 B | 🚀 **83.6%** |
| **Benchmark** | `scripts/benchmark_papers.sh`| 6,516 B | 1,120 B | 🚀 **82.8%** |
| **Automation** | `rulebook/AGENT_AUTO.md` | 4,493 B | 810 B | 🚀 **82.0%** |
| **Firewall** | `rules.json` | 3,465 B | 1,110 B | 🚀 **67.9%** |
| **Wix Schema** | `wix/main.wxs` | 3,306 B | 910 B | 🚀 **72.5%** |
| **Quality** | `rulebook/QUALITY.md` | 2,871 B | 610 B | 🚀 **78.7%** |
| **C++ Header** | `cpp/docling_ffi.h` | 1,699 B | 410 B | 🚀 **75.9%** |
| **Container** | `Dockerfile` | 1,187 B | 450 B | 🚀 **62.1%** |
| **Linter** | `clippy.toml` | 472 B | 210 B | 🚀 **55.5%** |

---

### 5. How We Measure Success

#### **Accuracy (Did we lose any needles?)**
Accuracy is measured using **Signal Integrity**. Before we crush a file, we identify every "High-Signal Token" (function names, variable names, error codes). We then verify that **100.0%** of these tokens exist in the output and are in the same relative order. If a single function name is missing, the accuracy is 0%. 

#### **Savings (How much hay did we remove?)**
Savings are calculated by the **Crush Ratio**: `1 - (Compressed Size / Original Size)`. Our goal for production code is always >70%, and for messy logs, our target is >90%.

**Transmutation makes AI agents faster, cheaper, and smarter by giving them the signal they need and none of the noise they don't.**
