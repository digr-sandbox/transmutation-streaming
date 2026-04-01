# Token-Oriented Object Notation (TOON)

TOON is a compact, token-efficient data serialization format explicitly designed for Large Language Models (LLMs) operating in agentic environments. It solves the massive context waste inherent in traditional structured formats like JSON, XML, and HTML by mathematically flattening their syntax without losing relational semantics.

## The Problem with JSON and XML
Traditional serialization formats were built for programmatic parsing, not for transformer-based tokenizers.
* **Redundancy**: In JSON, an array of 100 objects with the key `"user_id"` repeats the string `"user_id"` 100 times.
* **Structural Bloat**: HTML and XML enforce closing tags (`</div>`, `</directory>`) and decorative punctuation (`"`, `{`, `}`) that consume valuable context tokens but provide zero additional meaning to an LLM.

## How Transmutation implements TOON
While inspired by existing TOON specifications, Transmutation provides a **dependency-free, native TOON Minifier** built directly into the engine. When the gateway detects a structured payload (via a try-parse waterfall), it automatically routes the text away from statistical pruning (which destroys syntax) and into the TOON squeezer.

The TOON squeezer achieves 40-80% compression ratios via three primary mechanisms:

### 1. Hierarchical Flattening
Deeply nested objects are flattened into dot-notation dictionaries.
**JSON:**
```json
{
  "server": {
    "status": 200,
    "config": { "port": 8080 }
  }
}
```
**TOON:**
```text
server.status:200 server.config.port:8080
```

### 2. Array Collapsing
Instead of repeating keys across an array of identical objects, TOON extracts the array length and collapses the values into a single, space-delimited stream.
**JSON:**
```json
{
  "directories": [
    { "dir": "src" },
    { "dir": "tests" }
  ]
}
```
**TOON:**
```text
directories[2]: src tests
```

### 3. Aggressive Tag & Quote Stripping
For XML and HTML, TOON functions as a semantic noise destroyer.
* It completely removes all closing tags (e.g., `</file>`).
* It simplifies opening tags to space-delimited attributes (e.g., `<file name="x"/>` becomes `file name=x`).
* It strips quotes from attribute values.
* It deletes purely semantic noise that doesn't aid the LLM's logic (e.g., `<!DOCTYPE>`, `<html>`, `<body>`).

## Implementation details in the Codebase
The custom TOON minifier is implemented directly in the context engine's routing logic.
If a command like `cat audit_logs/latest.json` or `curl localhost:8080/api` is executed, the engine attempts to `serde_json::from_str`. If successful, the JSON is recursively flattened.

If the output begins with `<` and ends with `>`, it is aggressively parsed with regex to strip closing tags and quotes before being served to the agent. This ensures maximum operational clarity with minimum token footprint.