# Token Crushing: Evaluation Deep Dive
## Moving Beyond Substring Matching to Topological Accuracy

To achieve "Production Ready" status for an agentic document engine, we cannot rely on hardcoded "important_bits" for every language. This document outlines the **Universal Information Geometry** strategy used to verify accuracy in a language-agnostic way.

---

### 1. Abstract Semantic Roles (The "Boring Table" Method)
Instead of telling the engine what is "important" (which is hard to maintain across languages), we tell it what is **"boring."**

*   **The Boring Table**: A list of the ~500 most frequent tokens in software engineering (`if`, `else`, `let`, `var`, `return`, `public`, `private`, `{`, `}`, `(` , `)`).
*   **The Identification Rule**: Any token that is **NOT** in the Boring Table AND contains "High-Information Markers" is classified as a **Needle**.
    *   **Needle Markers**: `@Decorators`, `snake_case`, `CamelCase`, `::namespacing`, `0xAddresses`.
*   **Agnostic Example**:
    *   In **TypeScript**, `@Injectable()` is complex and not boring.
    *   In **C**, `ConversionResult*` is complex and not boring.
    *   In **Go**, `DocumentConverter` is complex and not boring.
*   **The Assertion**: 100% of these identified "Needles" MUST survive the crushing process.

---

### 2. Proximity Assertions (Preserving Context)
Accuracy isn't just about finding the word; it's about preserving the **Spatial Relationship** between needles.

*   **The Principle of Physicality**: In every language, an attribute and its subject are physically adjacent.
*   **Example (The "Broken Anchor" Problem)**:
    *   **Original**: `auth.service.ts` line 42 contains `@Injectable()`.
    *   **Crushed**: `auth.service.ts` line 1 ... (500 lines pruned) ... `@Injectable()`.
    *   **Result**: Even though both tokens exist, the **Contextual Accuracy is 0%** because the "Anchor" (the file path) is too far from the "Signal" (the decorator).
*   **The Test**: We assert that if Needle A and Needle B were within `N` tokens of each other in the source, they must remain within `N` tokens in the output.

---

### 3. The Mutation Engine (Generating "Many Tests per File")
To ensure we don't just "pass" by accident, we use **Synthetic Noise Injection** to turn 1 asset file into 100+ unique stress tests.

#### Variation A: The "Needle in a Haystack"
We take a single function from `permissions.service.ts` and wrap it in 5,000 lines of randomly sampled "Garbage" (e.g., license headers, minified JS noise from `node_modules`).
*   **Goal**: The engine must prune >99% of the garbage but keep the function signature perfectly intact.

#### Variation B: The "Fragmentation" Window
We slide a 500-line "Operational Window" across a large file. 
*   **Goal**: Ensure that if a "Needle" is partially cut off by the window boundary, the engine handles the **Partial Context** gracefully rather than hallucinating a new structure.

#### Variation C: The "Permutation" Shuffle
We identify independent logic blocks (e.g., separate classes in a file) and shuffle their order.
*   **Goal**: Verify that the **Relational Integrity** inside each block remains 100% stable regardless of its global position.

---

### 4. Mathematical Accuracy Scoring
A test is only marked as **PASS** if it meets the **Composite Accuracy Score (CAS)**:

`CAS = (Signal Survival) * (Proximity Stability) * (Compression Efficiency)`

1.  **Signal Survival**: Did all high-entropy needles survive?
2.  **Proximity Stability**: Did the needles stay near their anchors?
3.  **Compression Efficiency**: Did we actually prune the noise? (Efficiency > 80%).

This strategy allows us to support any new language (Zig, Mojo, Carbon) instantly, because the **Information Geometry** of code is universal.
