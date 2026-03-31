use std::collections::{HashMap, HashSet};
use std::time::Instant;

/// --- THE PRUNING SUITE: Core Algorithms ---

#[derive(Clone)]
struct Config {
    idf_weight: f64,
    pos_weight: f64,
    entropy_weight: f64,
    compression_ratio: f64,
}

struct WordAudit {
    text: String,
    final_score: f64,
    kept: bool,
}

fn run_suite(words: &[String], config: &Config) -> Vec<WordAudit> {
    // 1. IDF Scoring (Global Context)
    let mut freq_map = HashMap::new();
    for w in words { *freq_map.entry(w).or_insert(0) += 1; }
    let total = words.len() as f64;

    // 2. Entropy Analysis (Local Context - 10 word window)
    let mut audits = Vec::new();
    const WINDOW: usize = 10;

    for (idx, word) in words.iter().enumerate() {
        // IDF
        let count = freq_map.get(word).unwrap_or(&1);
        let idf = (total / *count as f64).ln();

        // POS (Stopword Heuristic)
        let stop_words: HashSet<&str> = ["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "with", "by", "from", "as", "it", "this", "that", "of", "be"].into_iter().collect();
        let pos = if stop_words.contains(word.to_lowercase().as_str()) { 0.1 } else { 0.8 };

        // Entropy (Diversity)
        let start = idx.saturating_sub(WINDOW / 2);
        let end = (idx + WINDOW / 2).min(words.len());
        let window = &words[start..end];
        let unique = window.iter().collect::<HashSet<_>>().len();
        let entropy = unique as f64 / window.len() as f64;

        // COMBINE: The Weighted Sum
        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight) + (entropy * config.entropy_weight);

        audits.push(WordAudit {
            text: word.clone(),
            final_score,
            kept: false,
        });
    }

    // 3. PRUNE: Keep top N% based on final_score
    let mut sorted_indices: Vec<usize> = (0..audits.len()).collect();
    sorted_indices.sort_by(|&a, &b| audits[b].final_score.partial_cmp(&audits[a].final_score).unwrap());
    
    let keep_count = (audits.len() as f64 * config.compression_ratio) as usize;
    for &idx in sorted_indices.iter().take(keep_count) {
        audits[idx].kept = true;
    }

    audits
}

/// --- TEST SUITE DATA ---

struct TestCase {
    category: &'static str,
    name: &'static str,
    input: String,
    important_bits: Vec<&'static str>,
}

fn get_test_cases() -> Vec<TestCase> {
    vec![
        // 1. Build Logs
        TestCase {
            category: "Build Logs",
            name: "NPM Success",
            input: "npm info it worked. npm info using npm@10.2.4. webpack compiled successfully in 1243ms. output saved to ./dist/main.js".to_string(),
            important_bits: vec!["successfully", "1243ms", "./dist/main.js"],
        },
        TestCase {
            category: "Build Logs",
            name: "Cargo Error",
            input: "error[E0432]: unresolved import `crate::missing`. --> src/lib.rs:10:5. 10 | use crate::missing; |     ^^^^^^^^^^^^^^. error: aborting due to previous error".to_string(),
            important_bits: vec!["E0432", "src/lib.rs", "unresolved"],
        },
        TestCase {
            category: "Build Logs",
            name: "CMake Spam",
            input: "-- Check for working C compiler: /usr/bin/cc. -- Check for working C compiler: /usr/bin/cc -- works. -- Detecting C compiler ABI info. -- Detecting C compiler ABI info - done".to_string(),
            important_bits: vec!["/usr/bin/cc", "works", "done"],
        },
        TestCase {
            category: "Build Logs",
            name: "Vite HMR",
            input: "10:15:01 AM [vite] hmr update /src/App.tsx. 10:15:02 AM [vite] hmr update /src/components/Button.tsx. page reloaded.".to_string(),
            important_bits: vec!["hmr", "update", "/src/App.tsx"],
        },
        TestCase {
            category: "Build Logs",
            name: "Go Test Fail",
            input: "--- FAIL: TestConversion (0.05s). conversion_test.go:45: expected 100, got 200. FAIL. exit status 1.".to_string(),
            important_bits: vec!["FAIL", "conversion_test.go", "45", "200"],
        },

        // 2. Server Logs
        TestCase {
            category: "Server Logs",
            name: "Nginx Access",
            input: "127.0.0.1 - - [30/Mar/2026:18:00:01 +0000] \"GET /api/v1/users HTTP/1.1\" 200 1243 \"-\" \"Mozilla/5.0\"".to_string(),
            important_bits: vec!["127.0.0.1", "/api/v1/users", "200"],
        },
        TestCase {
            category: "Server Logs",
            name: "Auth Error",
            input: "AUTH_ERROR: Failed login attempt for user 'admin' from IP 192.168.1.50. reason: invalid_password. attempts: 3.".to_string(),
            important_bits: vec!["AUTH_ERROR", "admin", "192.168.1.50", "invalid_password"],
        },
        TestCase {
            category: "Server Logs",
            name: "JSON Log",
            input: "{\"level\":\"info\",\"ts\":1711821600,\"msg\":\"request processed\",\"path\":\"/health\",\"status\":200,\"latency_ms\":5}".to_string(),
            important_bits: vec!["/health", "200", "5"],
        },
        TestCase {
            category: "Server Logs",
            name: "Slow Query",
            input: "SLOW_QUERY: SELECT * FROM orders WHERE user_id = 500. duration: 1500ms. rows: 50000.".to_string(),
            important_bits: vec!["SLOW_QUERY", "orders", "1500ms"],
        },
        TestCase {
            category: "Server Logs",
            name: "K8s Health",
            input: "kubelet: Readiness probe failed: HTTP probe failed with statuscode: 500. pod: transmutation-proxy-xyz. node: worker-1.".to_string(),
            important_bits: vec!["Readiness", "failed", "500", "transmutation-proxy-xyz"],
        },

        // 3. Code
        TestCase {
            category: "Code",
            name: "Rust Impl",
            input: "impl DocumentConverter for PdfConverter { async fn convert(&self, path: &Path) -> Result<ConversionResult> { let pdf = lopdf::Document::load(path)?; Ok(pdf) } }".to_string(),
            important_bits: vec!["PdfConverter", "convert", "lopdf"],
        },
        TestCase {
            category: "Code",
            name: "Python Class",
            input: "class DataProxy: \"\"\"A proxy for data streams\"\"\" def __init__(self, limit: int): self.limit = limit. def stream(self): return self.data[:self.limit]".to_string(),
            important_bits: vec!["DataProxy", "__init__", "limit"],
        },
        TestCase {
            category: "Code",
            name: "JS Component",
            input: "const Button = ({ label, onClick }) => { return <button onClick={onClick}>{label}</button>; }; export default Button;".to_string(),
            important_bits: vec!["Button", "label", "onClick"],
        },
        TestCase {
            category: "Code",
            name: "Go Interface",
            input: "type Storage interface { Read(key string) ([]byte, error). Write(key string, data []byte) error. }".to_string(),
            important_bits: vec!["Storage", "Read", "Write"],
        },
        TestCase {
            category: "Code",
            name: "SQL Schema",
            input: "CREATE TABLE users ( id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE NOT NULL, created_at TIMESTAMP DEFAULT NOW() );".to_string(),
            important_bits: vec!["users", "SERIAL", "email"],
        },

        // 4. Grep Results
        TestCase {
            category: "Grep Results",
            name: "Path Search",
            input: "src/lib.rs:45: pub fn convert. src/bin/main.rs:12: let c = Converter::new(). src/utils/mod.rs:2: pub use file_detect;".to_string(),
            important_bits: vec!["src/lib.rs", "convert", "src/bin/main.rs"],
        },
        TestCase {
            category: "Grep Results",
            name: "Secret Scan",
            input: ".env:12: API_KEY=sk-1234567890. config.yaml:5: secret: \"my-secret-token\". README.md:1: # Project Secret".to_string(),
            important_bits: vec!["API_KEY", "sk-1234567890", "secret"],
        },
        TestCase {
            category: "Grep Results",
            name: "TODO List",
            input: "src/converters/pdf.rs:89: // TODO: fix OOM. src/converters/txt.rs:10: // FIXME: newline bug. tests/integration.rs:1: // TODO: add more tests".to_string(),
            important_bits: vec!["OOM", "newline", "FIXME"],
        },
        TestCase {
            category: "Grep Results",
            name: "Imports",
            input: "Cargo.toml:5: tokio = \"1.0\". Cargo.toml:6: serde = \"1.0\". Cargo.toml:10: lopdf = \"0.35\"".to_string(),
            important_bits: vec!["tokio", "serde", "lopdf"],
        },
        TestCase {
            category: "Grep Results",
            name: "Errors",
            input: "logs/app.log: error: db down. logs/app.log: error: timeout. logs/sys.log: kernel panic at 0x00123".to_string(),
            important_bits: vec!["error", "panic", "0x00123"],
        },

        // 5. LLM Prompt
        TestCase {
            category: "LLM Prompt",
            name: "Instruction",
            input: "You are a senior Rust engineer. Follow these rules: 1. No unsafe code. 2. Deny panics. 3. Use async where possible. Respond concisely.".to_string(),
            important_bits: vec!["senior", "Rust", "unsafe", "async"],
        },
        TestCase {
            category: "LLM Prompt",
            name: "Conversation",
            input: "User: how do I fix OOM? Assistant: You should use streaming. User: show me the code. Assistant: here is the implementation.".to_string(),
            important_bits: vec!["OOM", "Assistant", "streaming"],
        },
        TestCase {
            category: "LLM Prompt",
            name: "XML Wrapped",
            input: "<context> Here is the file: <file> src/main.rs </file> </context> <instruction> Refactor this class </instruction>".to_string(),
            important_bits: vec!["<context>", "src/main.rs", "<instruction>"],
        },
        TestCase {
            category: "LLM Prompt",
            name: "Few Shot",
            input: "Example 1: a -> b. Example 2: c -> d. Example 3: e -> f. Now do: x -> ?".to_string(),
            important_bits: vec!["Example", "Now", "do"],
        },
        TestCase {
            category: "LLM Prompt",
            name: "System Log",
            input: "System: initialized. Mode: streaming. Version: 0.4.0. Status: healthy. Ready for input.".to_string(),
            important_bits: vec!["Mode", "0.4.0", "Status"],
        },

        // 6. SQL Query Logs
        TestCase {
            category: "SQL Logs",
            name: "Complex Join",
            input: "SELECT u.email, o.total FROM users u JOIN orders o ON u.id = o.user_id WHERE o.total > 1000 ORDER BY o.created_at DESC;".to_string(),
            important_bits: vec!["JOIN", "orders", "1000", "DESC"],
        },
        TestCase {
            category: "SQL Logs",
            name: "Insert Multi",
            input: "INSERT INTO logs (level, msg) VALUES ('info', 'started'), ('warn', 'slow'), ('error', 'failed');".to_string(),
            important_bits: vec!["INSERT", "logs", "VALUES"],
        },
        TestCase {
            category: "SQL Logs",
            name: "Constraint Fail",
            input: "ERROR: duplicate key value violates unique constraint \"users_email_key\". DETAIL: Key (email)=(test@example.com) already exists.".to_string(),
            important_bits: vec!["duplicate", "unique", "users_email_key", "test@example.com"],
        },
        TestCase {
            category: "SQL Logs",
            name: "Migration",
            input: "BEGIN; ALTER TABLE users ADD COLUMN phone VARCHAR(20); CREATE INDEX idx_users_phone ON users(phone); COMMIT;".to_string(),
            important_bits: vec!["ALTER", "ADD", "INDEX"],
        },
        TestCase {
            category: "SQL Logs",
            name: "Drop Table",
            input: "DROP TABLE legacy_data; TRUNCATE audit_logs; VACUUM ANALYZE;".to_string(),
            important_bits: vec!["DROP", "TRUNCATE", "VACUUM"],
        },

        // 7. Git Output
        TestCase {
            category: "Git Output",
            name: "Git Diff",
            input: "--- a/src/lib.rs. +++ b/src/lib.rs. @@ -10,5 +10,6 @@. - let x = 1;. + let x = 2;. + let y = 3;".to_string(),
            important_bits: vec!["src/lib.rs", "let", "x", "y"],
        },
        TestCase {
            category: "Git Output",
            name: "Git Log",
            input: "commit 31d6ae6. Author: ericdigr. Date: Mon Mar 30. feat(cli): Implement magic byte sniffing".to_string(),
            important_bits: vec!["31d6ae6", "ericdigr", "sniffing"],
        },
        TestCase {
            category: "Git Output",
            name: "Git Status",
            input: "On branch main. Changes not staged for commit: modified: src/bin/transmutation.rs. Untracked files: examples/test.rs".to_string(),
            important_bits: vec!["modified", "src/bin/transmutation.rs", "untracked"],
        },
        TestCase {
            category: "Git Output",
            name: "Git Pull",
            input: "Updating 934c1b0..31d6ae6. Fast-forward. src/bin/transmutation.rs | 36 ++++++++++++++++-. 1 file changed, 30 insertions(+), 6 deletions(-)".to_string(),
            important_bits: vec!["Fast-forward", "insertions", "deletions"],
        },
        TestCase {
            category: "Git Output",
            name: "Git Remote",
            input: "origin  https://github.com/hivellm/transmutation.git (fetch). origin  https://github.com/hivellm/transmutation.git (push)".to_string(),
            important_bits: vec!["origin", "github.com", "push"],
        },
    ]
}

fn main() {
    let test_cases = get_test_cases();
    let config = Config {
        idf_weight: 0.3,
        pos_weight: 0.4,
        entropy_weight: 0.3,
        compression_ratio: 0.5, // Target 50%
    };

    println!("🧪 COMPREHENSIVE PRUNING SUITE EVALUATION");
    println!("Weights: IDF:{:.1} POS:{:.1} Ent:{:.1} Target:{:.0}%", config.idf_weight, config.pos_weight, config.entropy_weight, config.compression_ratio * 100.0);
    println!("================================================================================\n");

    println!("{:<15} | {:<15} | {:<10} | {:<10} | {:<10}", "Category", "Test Name", "Bytes", "Tokens", "Status");
    println!("{:-<80}", "");

    let mut overall_failures = 0;

    for tc in test_cases {
        let words: Vec<String> = tc.input.split_whitespace().map(|s| s.to_string()).collect();
        let result = run_suite(&words, &config);

        // Calculate Ratios
        let original_bytes = tc.input.len();
        let mut pruned_text = String::new();
        let mut kept_tokens = 0;
        
        for r in &result {
            if r.kept {
                pruned_text.push_str(&r.text);
                pruned_text.push(' ');
                kept_tokens += 1;
            }
        }
        let pruned_bytes = pruned_text.trim().len();
        
        let byte_ratio = pruned_bytes as f64 / original_bytes as f64;
        let token_ratio = kept_tokens as f64 / words.len() as f64;

        // Verify "Important Bits"
        let mut missed_bits = Vec::new();
        for bit in &tc.important_bits {
            if !pruned_text.contains(bit) {
                missed_bits.push(*bit);
            }
        }

        let status = if missed_bits.is_empty() {
            "✅ PASS".green()
        } else {
            overall_failures += 1;
            format!("❌ FAIL ({})", missed_bits.len()).red()
        };

        println!("{:<15} | {:<15} | {:<10.1}% | {:<10.1}% | {}", tc.category, tc.name, byte_ratio * 100.0, token_ratio * 100.0, status);
        
        if !missed_bits.is_empty() {
            println!("   ↳ Lost bits: {:?}", missed_bits);
        }
    }

    println!("\n{:-<80}", "");
    println!("📊 SUMMARY: {} failures in {} test cases.", overall_failures, get_test_cases().len());
}

// Minimal implementation of 'colored' for standalone example if not available
trait Colorize {
    fn green(&self) -> String;
    fn red(&self) -> String;
}
impl Colorize for &str {
    fn green(&self) -> String { format!("\x1b[32m{}\x1b[0m", self) }
    fn red(&self) -> String { format!("\x1b[31m{}\x1b[0m", self) }
}
impl Colorize for String {
    fn green(&self) -> String { format!("\x1b[32m{}\x1b[0m", self) }
    fn red(&self) -> String { format!("\x1b[31m{}\x1b[0m", self) }
}
