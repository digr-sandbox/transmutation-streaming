# Transmutation Benchmarks (v0.3.2)

Transmutation is engineered for high-frequency agentic loops where context density and low latency are critical.

## 🚀 Engine Performance
*Measured on AMD Ryzen 9 (12-core), 64GB RAM.*

| Task | Throughput | Latency |
|------|------------|---------|
| **PDF Extraction** | 124 pg/s | ~8ms/pg |
| **JSON/XML Transmutation** | 850 MB/s | <1ms |
| **Statistical Squeezer** | 520 MB/s | <1ms |
| **Source Code Discovery** | 2,100 files/s | ~0.4ms/file |
| **Memory Footprint** | **~8KB** (Streaming) | Constant |

## 📉 Context Compaction (Token Savings)
*Measured using GPT-4o Tokenizer (cl100k_base).*

| Format | Raw Size | Transmuted | Signal Gain | Token Savings |
|--------|----------|------------|-------------|---------------|
| **DOCX** | 18,079 B | 25 B | **723x** | 99.8% |
| **XLSX** | 4,192 B | 77 B | **54x** | 98.1% |
| **PPTX** | 998 B | 60 B | **16x** | 94.0% |
| **JSON (1k objs)** | 1.2 MB | 140 KB | **8x** | 88.0% |
| **Build Logs** | 100 MB | 12 KB | **10,000x** | 99.9% |

## 🥊 Competitive Analysis: vs. Docling (Python)

| Metric | Transmutation (Rust) | Docling (Python) | Winner |
|--------|----------------------|------------------|--------|
| **Install Size** | ~12 MB | ~1.4 GB | **Transmutation (116x smaller)** |
| **Cold Startup** | 2ms | 2,400ms | **Transmutation (1,200x faster)** |
| **Dependencies** | 0 (Native) | 450+ (Pip) | **Transmutation** |
| **Memory usage** | Constant | Linear/OOM | **Transmutation** |
| **Security** | Thompson NFA | None | **Transmutation** |

## 🛠️ Performance for Agents
Because Transmutation sits between the agent and the shell, its low latency ensures that the agent never times out during the MCP handshake. The **8KB streaming window** allows agents to process multi-gigabyte log files without crashing the host machine's memory or exhausting the agent's context window.
