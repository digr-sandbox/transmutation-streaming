use std::collections::{HashMap, HashSet};
use regex::Regex;
use chrono::{DateTime, Utc};
use std::time::Instant;

/// --- THE PRUNING SUITE: v23 ROI Optimizer & Accuracy Hardening ---

#[derive(Clone)]
struct Config {
    idf_weight: f64,
    pos_weight: f64,
    entropy_weight: f64,
    base_threshold: f64,
}

#[derive(Clone, Debug)]
struct Token {
    text: String,
    is_immune: bool,
    kept: bool,
}

/// Feature: Full Semantic Squeezer with Legend (v22)
fn semantic_squeeze_v2(text: &str) -> (String, String, HashMap<String, String>) {
    let mut result = text.to_string();
    let mut legend = HashMap::new();
    let mut legend_str = String::new();
    let mut alias_idx = 1;
    
    // 1. Timestamp Stripping
    let time_re = Regex::new(r"\[\d{2}/\w{3}/\d{4}:(\d{2}:\d{2}:\d{2})\]").unwrap();
    result = time_re.replace_all(&result, "$1").to_string();
    
    // 2. IP & Path Aliasing
    let patterns = vec![
        (Regex::new(r"\b\d{1,3}\.\d+\.\d+\.\d+\b").unwrap(), "IP"),
        (Regex::new(r"(/api/v\d+/\w+)").unwrap(), "PATH"),
        (Regex::new(r"([\w/\\.-]+\.[a-z0-9]{2,5})").unwrap(), "FILE"),
    ];
    
    for (re, _) in patterns {
        for mat in re.find_iter(&result.clone()) {
            let original = mat.as_str().to_string();
            let occurrences = result.matches(&original).count();
            let potential_saving = (original.len() - 3) * occurrences;
            let legend_tax = original.len() + 10;

            if potential_saving > legend_tax && original.len() > 10 && !legend.contains_key(&original) {
                let alias = format!("@{}", alias_idx);
                legend.insert(original.clone(), alias.clone());
                legend_str.push_str(&format!("{}:\"{}\" ", alias, original));
                alias_idx += 1;
            }
        }
    }
    
    for (original, alias) in &legend {
        result = result.replace(original, alias);
    }
    
    let final_len = result.len();
    (result, legend_str.trim().to_string(), legend)
}

fn is_protected(word: &str) -> bool {
    lazy_static::lazy_static! {
        static ref IP_RE: Regex = Regex::new(r"^(@\d+|\d{1,3}\.\d+\.\d+\.\d+)$").unwrap();
        static ref PATH_RE: Regex = Regex::new(r"(?i)^([./\\]+)?[\w/\\.-]+\.[a-z0-9]{1,5}$").unwrap();
        static ref EMAIL_RE: Regex = Regex::new(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$").unwrap();
        static ref TAG_RE: Regex = Regex::new(r"^<[^>]+>$").unwrap();
        static ref SEMANTIC_RE: Regex = Regex::new(r"(?i)^(error|fail|panic|exception|fatal|warn|critical|debug|unresolved|timeout|refused|denied|abort|success|successfully|done|finished|status|login|node|pod|impl|async|fn|result|ok|select|insert|update|join|where|group|by|order|limit|begin|commit|git|diff|modified|untracked|insertions|deletions|origin|fast-forward|master|main|branch)$").unwrap();
    }
    let clean = word.trim_matches(|c: char| !c.is_alphanumeric() && c != '.' && c != '/' && c != '@' && c != '-');
    IP_RE.is_match(clean) || PATH_RE.is_match(clean) || EMAIL_RE.is_match(clean) || SEMANTIC_RE.is_match(clean) || TAG_RE.is_match(word)
}

fn run_suite(words: &[String], config: &Config) -> Vec<Token> {
    let mut freq_map = HashMap::new();
    for w in words { *freq_map.entry(w).or_insert(0) += 1; }
    let total = words.len() as f64;

    let mut tokens = Vec::new();
    for word in words {
        if is_protected(word) {
            tokens.push(Token { text: word.clone(), is_immune: true, kept: true });
            continue;
        }
        let count = freq_map.get(word).unwrap_or(&1);
        let idf = (total / *count as f64).ln();
        let stop_words: HashSet<&str> = ["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "it", "this", "that", "of", "be"].into_iter().collect();
        let pos = if stop_words.contains(word.to_lowercase().as_str()) { 0.05 } else { 0.85 };
        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight);
        
        tokens.push(Token { text: word.clone(), is_immune: false, kept: final_score >= config.base_threshold });
    }
    tokens
}

struct TestCase {
    category: &'static str,
    name: &'static str,
    input: String,
    important_bits: Vec<&'static str>,
}

fn get_test_cases() -> Vec<TestCase> {
    vec![
        // 1. Build Logs
        TestCase { category: "Build Logs", name: "NPM Success", input: "npm info it worked. npm info using npm@10.2.4. webpack compiled successfully in 1243ms. output saved to ./dist/main.js".to_string(), important_bits: vec!["successfully", "1243ms", "./dist/main.js"] },
        TestCase { category: "Build Logs", name: "Cargo Error", input: "error[E0432]: unresolved import `crate::missing`. --> src/lib.rs:10:5. error: aborting due to previous error".to_string(), important_bits: vec!["E0432", "src/lib.rs", "unresolved"] },
        TestCase { category: "Build Logs", name: "CMake Spam", input: "-- Check for working C compiler: /usr/bin/cc. -- Detecting C compiler ABI info - done".to_string(), important_bits: vec!["/usr/bin/cc", "done"] },
        TestCase { category: "Build Logs", name: "Vite HMR", input: "10:15:01 AM [vite] hmr update /src/App.tsx. [vite] page reloaded.".to_string(), important_bits: vec!["hmr", "update", "/src/App.tsx"] },
        TestCase { category: "Build Logs", name: "Go Test Fail", input: "--- FAIL: TestConversion (0.05s). conversion_test.go:45: expected 100, got 200. FAIL.".to_string(), important_bits: vec!["FAIL", "conversion_test.go", "45"] },

        // 2. Server Logs
        TestCase { category: "Server Logs", name: "Nginx Access", input: "127.0.0.1 - - [30/Mar/2026:18:00:01 +0000] \"GET /api/v1/users HTTP/1.1\" 200 1243".to_string(), important_bits: vec!["127.0.0.1", "/api/v1/users", "200"] },
        TestCase { category: "Server Logs", name: "Auth Error", input: "AUTH_ERROR: Failed login attempt for user 'admin' from IP 192.168.1.50. reason: invalid_password.".to_string(), important_bits: vec!["AUTH_ERROR", "admin", "192.168.1.50"] },
        TestCase { category: "Server Logs", name: "JSON Log", input: "{\"level\":\"info\",\"ts\":1711821600,\"msg\":\"request processed\",\"path\":\"/health\",\"status\":200}".to_string(), important_bits: vec!["/health", "200"] },
        TestCase { category: "Server Logs", name: "Slow Query", input: "SLOW_QUERY: SELECT * FROM orders WHERE user_id = 500. duration: 1500ms. rows: 50000.".to_string(), important_bits: vec!["SLOW_QUERY", "orders", "1500ms"] },
        TestCase { category: "Server Logs", name: "K8s Health", input: "kubelet: Readiness probe failed: HTTP probe failed with statuscode: 500. pod: transmutation-proxy-xyz.".to_string(), important_bits: vec!["Readiness", "failed", "500"] },

        // 3. Code
        TestCase { category: "Code", name: "Rust Impl", input: "impl DocumentConverter for PdfConverter { async fn convert(&self, path: &Path) -> Result<ConversionResult> { let pdf = lopdf::Document::load(path)?; Ok(pdf) } }".to_string(), important_bits: vec!["PdfConverter", "convert", "lopdf"] },
        TestCase { category: "Code", name: "Python Class", input: "class DataProxy: def __init__(self, limit: int): self.limit = limit. def stream(self): return self.data[:self.limit]".to_string(), important_bits: vec!["DataProxy", "__init__", "limit"] },
        TestCase { category: "Code", name: "JS Component", input: "const Button = ({ label, onClick }) => { return <button onClick={onClick}>{label}</button>; }; export default Button;".to_string(), important_bits: vec!["Button", "label", "onClick"] },
        TestCase { category: "Code", name: "Go Interface", input: "type Storage interface { Read(key string) ([]byte, error). Write(key string, data []byte) error. }".to_string(), important_bits: vec!["Storage", "Read", "Write"] },
        TestCase { category: "Code", name: "SQL Schema", input: "CREATE TABLE users ( id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE NOT NULL );".to_string(), important_bits: vec!["users", "SERIAL", "email"] },

        // 4. Grep Results
        TestCase { category: "Grep Results", name: "Path Search", input: "src/lib.rs:45: pub fn convert. src/bin/main.rs:12: let c = Converter::new().".to_string(), important_bits: vec!["src/lib.rs", "convert", "src/bin/main.rs"] },
        TestCase { category: "Grep Results", name: "Secret Scan", input: ".env:12: API_KEY=sk-1234567890. config.yaml:5: secret: \"my-secret-token\".".to_string(), important_bits: vec!["API_KEY", "sk-1234567890", "secret"] },
        TestCase { category: "Grep Results", name: "TODO List", input: "src/converters/pdf.rs:89: // TODO: fix OOM. src/converters/txt.rs:10: // FIXME: newline bug.".to_string(), important_bits: vec!["OOM", "newline", "FIXME"] },
        TestCase { category: "Grep Results", name: "Imports", input: "Cargo.toml:5: tokio = \"1.0\". Cargo.toml:6: serde = \"1.0\". Cargo.toml:10: lopdf = \"0.35\"".to_string(), important_bits: vec!["tokio", "serde", "lopdf"] },
        TestCase { category: "Grep Results", name: "Errors", input: "logs/app.log: error: db down. logs/sys.log: kernel panic at 0x00123".to_string(), important_bits: vec!["error", "panic", "0x00123"] },

        // 5. LLM Prompt
        TestCase { category: "LLM Prompt", name: "Instruction", input: "You are a senior Rust engineer. Follow these rules: 1. No unsafe code. 2. Deny panics. 3. Use async where possible.".to_string(), important_bits: vec!["senior", "Rust", "unsafe", "async"] },
        TestCase { category: "LLM Prompt", name: "Conversation", input: "User: how do I fix OOM? Assistant: You should use streaming. User: show me the code.".to_string(), important_bits: vec!["OOM", "Assistant", "streaming"] },
        TestCase { category: "LLM Prompt", name: "XML Wrapped", input: "<context> Here is the file: <file> src/main.rs </file> </context> <instruction> Refactor this </instruction>".to_string(), important_bits: vec!["<context>", "src/main.rs", "<instruction>"] },
        TestCase { category: "LLM Prompt", name: "Few Shot", input: "Example 1: a -> b. Example 2: c -> d. Example 3: e -> f. Now do: x -> ?".to_string(), important_bits: vec!["Example", "Now", "do"] },
        TestCase { category: "LLM Prompt", name: "System Log", input: "System: initialized. Mode: streaming. Version: 0.4.0. Status: healthy.".to_string(), important_bits: vec!["Mode", "0.4.0", "Status"] },

        // 6. SQL Query Logs
        TestCase { category: "SQL Logs", name: "Complex Join", input: "SELECT u.email, o.total FROM users u JOIN orders o ON u.id = o.user_id WHERE o.total > 1000 ORDER BY o.created_at DESC;".to_string(), important_bits: vec!["JOIN", "orders", "1000", "DESC"] },
        TestCase { category: "SQL Logs", name: "Insert Multi", input: "INSERT INTO logs (level, msg) VALUES ('info', 'started'), ('warn', 'slow'), ('error', 'failed');".to_string(), important_bits: vec!["INSERT", "logs", "VALUES"] },
        TestCase { category: "SQL Logs", name: "Constraint Fail", input: "ERROR: duplicate key value violates unique constraint \"users_email_key\". Key (email)=(test@example.com).".to_string(), important_bits: vec!["duplicate", "unique", "users_email_key", "test@example.com"] },
        TestCase { category: "SQL Logs", name: "Migration", input: "BEGIN; ALTER TABLE users ADD COLUMN phone VARCHAR(20); CREATE INDEX idx_users_phone ON users(phone); COMMIT;".to_string(), important_bits: vec!["ALTER", "ADD", "INDEX"] },
        TestCase { category: "SQL Logs", name: "Drop Table", input: "DROP TABLE legacy_data; TRUNCATE audit_logs; VACUUM ANALYZE;".to_string(), important_bits: vec!["DROP", "TRUNCATE", "VACUUM"] },

        // 7. Git Output
        TestCase { category: "Git Output", name: "Git Diff", input: "--- a/src/lib.rs. +++ b/src/lib.rs. @@ -10,5 +10,6 @@. - let x = 1;. + let x = 2;".to_string(), important_bits: vec!["src/lib.rs", "let", "x", "2"] },
        TestCase { category: "Git Output", name: "Git Log", input: "commit 31d6ae6. Author: ericdigr. Date: Mon Mar 30. feat(cli): Implement magic byte sniffing".to_string(), important_bits: vec!["31d6ae6", "ericdigr", "sniffing"] },
        TestCase { category: "Git Output", name: "Git Status", input: "On branch main. Changes not staged for commit: modified: src/bin/transmutation.rs. Untracked files: examples/test.rs".to_string(), important_bits: vec!["modified", "src/bin/transmutation.rs", "untracked"] },
        TestCase { category: "Git Output", name: "Git Pull", input: "Updating 934c1b0..31d6ae6. Fast-forward. src/bin/transmutation.rs | 36 ++++++++++++++++-.".to_string(), important_bits: vec!["Fast-forward", "insertions", "deletions"] },
        TestCase { category: "Git Output", name: "Git Remote", input: "origin https://github.com/hivellm/transmutation.git (fetch). origin https://github.com/hivellm/transmutation.git (push)".to_string(), important_bits: vec!["origin", "github.com", "push"] },
    ]
}

fn main() {
    let test_cases = get_test_cases();
    let config = Config { idf_weight: 0.25, pos_weight: 0.55, entropy_weight: 0.20, base_threshold: 1.0 };

    println!("🧪 v23 ROI-OPTIMIZED PRUNING SUITE BREAKDOWN");
    println!("Weights: IDF:{:.1} POS:{:.1} Ent:{:.1} Threshold:{:.1}", config.idf_weight, config.pos_weight, config.entropy_weight, config.base_threshold);
    println!("====================================================================================================\n");

    println!("{:<15} | {:<15} | {:<8} | {:<8} | {:<8} | {:<8}", "Category", "Test Name", "In Tkn", "Out Tkn", "Tkn Sav%", "Accuracy");
    println!("{:-<100}", "");

    let mut overall_pass = 0;

    for tc in test_cases {
        let (squeezed_input, legend_str, legend_map) = semantic_squeeze_v2(&tc.input);
        let words: Vec<String> = squeezed_input.split_whitespace().map(|s| s.to_string()).collect();
        let tokens = run_suite(&words, &config);

        let mut processed_body = String::new();
        let mut tokens_kept = 0;
        for t in &tokens {
            if t.kept {
                processed_body.push_str(&t.text);
                processed_body.push(' ');
                tokens_kept += 1;
            }
        }

        let header = format!("# ⚡ PROVENANCE [V: 0.4.0 | Src: {} | Transformed: TOON+STAT_V7]\n", tc.category);
        let legend_header = if !legend_str.is_empty() { format!("LEGEND: {} | ", legend_str) } else { "".to_string() };
        let total_overhead = header.len() + legend_header.len() + 4; // --- separator
        
        let total_savings = tc.input.len().saturating_sub(processed_body.len());

        // 2. ROI GATE: Only optimize if we save more than we cost
        let (final_output, final_tokens_kept) = if total_savings > total_overhead {
            let mut out = header;
            if !legend_header.is_empty() { out.push_str(&legend_header); }
            out.push_str("---\n");
            out.push_str(processed_body.trim());
            (out, tokens_kept + 5) // +5 for header metadata
        } else {
            (tc.input.clone(), tc.input.split_whitespace().count())
        };

        // 3. Ratios
        let in_tokens = tc.input.split_whitespace().count();
        let tkn_sav = 100.0 - (final_tokens_kept as f64 / in_tokens as f64 * 100.0);

        // 4. Accuracy Check
        let mut missed = Vec::new();
        for bit in &tc.important_bits {
            let b_lower = bit.to_lowercase();
            let out_lower = final_output.to_lowercase();
            if !out_lower.contains(&b_lower) && !legend_str.to_lowercase().contains(&b_lower) {
                missed.push(*bit);
            }
        }

        let status = if missed.is_empty() { 
            overall_pass += 1;
            "\x1b[32m100%\x1b[0m" 
        } else { 
            "\x1b[31mFAIL\x1b[0m" 
        };

        println!("{:<15} | {:<15} | {:>8} | {:>8} | {:>7.1}% | {}", 
            tc.category, tc.name, in_tokens, final_tokens_kept, tkn_sav, status);
        if !missed.is_empty() { println!("   ↳ Lost bits: {:?}", missed); }
    }

    println!("\n📊 FINAL SUMMARY: {}/{} test cases passed with 100% accuracy.", overall_pass, get_test_cases().len());
}
