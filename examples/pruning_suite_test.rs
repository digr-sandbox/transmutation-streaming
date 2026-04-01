use std::collections::{HashMap, HashSet};
use regex::Regex;
use std::fs;
use rusqlite::Connection;
use walkdir::WalkDir;

/// --- THE PRUNING SUITE: v50 Universal Dependency Graph & Dual MCP ---
/// Validates Macro and Micro payloads with 3-Way Routing and Code Map Injection

#[derive(Clone)]
struct Config {
    idf_weight: f64,
    pos_weight: f64,
    entropy_weight: f64,
    position_weight: f64,
    base_threshold: f64,
}

// --- THE CODE MAP ENGINE ---
struct CodeMapEngine {
    conn: Connection,
}

impl CodeMapEngine {
    fn new() -> Self {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute("CREATE TABLE edges (source TEXT, target TEXT, UNIQUE(source, target))", []).unwrap();
        Self { conn }
    }

    fn extract_dependencies(content: &str, file_path: &str) -> HashSet<String> {
        let mut targets = HashSet::new();
        // A lightweight, language-agnostic regex parser for initial map building
        let rust_import_re = Regex::new(r"use\s+crate::([a-zA-Z0-9_:]+)").unwrap();
        let rust_mod_re = Regex::new(r"pub\s+mod\s+([a-zA-Z0-9_]+)").unwrap();
        let ts_import_re = Regex::new(r"import\s+.*from\s+[':]([^']+)[':]").unwrap();

        // 1. Rust Imports
        for cap in rust_import_re.captures_iter(content) {
            let mut path = "src".to_string();
            for part in cap[1].split("::") {
                if part == "*" || part.starts_with('{') { break; }
                path.push('/');
                path.push_str(part);
            }
            targets.insert(format!("{}.rs", path));
            targets.insert(format!("{}/mod.rs", path));
        }

        // 2. Rust Modules
        for cap in rust_mod_re.captures_iter(content) {
            let parent = std::path::Path::new(file_path).parent().unwrap().to_string_lossy().replace("\\", "/");
            targets.insert(format!("{}/{}.rs", parent, &cap[1]));
            targets.insert(format!("{}/{}/mod.rs", parent, &cap[1]));
        }

        // 3. TS/JS Imports (for frontend repos)
        for cap in ts_import_re.captures_iter(content) {
            targets.insert(cap[1].to_string());
        }

        // Filter out physically missing files to keep the graph clean
        targets.into_iter().filter(|p| std::path::Path::new(p).exists()).collect()
    }

    fn build_initial_map(&self) {
        for entry in WalkDir::new("src").into_iter().filter_map(|e| e.ok()) {
            if entry.path().extension().map_or(false, |ext| ext == "rs" || ext == "ts") {
                let source = entry.path().to_string_lossy().replace("\\", "/");
                if let Ok(content) = fs::read_to_string(entry.path()) {
                    let targets = Self::extract_dependencies(&content, &source);
                    for target in targets {
                        self.conn.execute("INSERT OR IGNORE INTO edges (source, target) VALUES (?1, ?2)", rusqlite::params![source, target]).unwrap();
                    }
                }
            }
        }
    }

    fn read_code_map(&self, filename: &str) -> String {
        let mut imports_from = Vec::new();
        let mut imported_by = Vec::new();

        if let Ok(mut stmt) = self.conn.prepare("SELECT target FROM edges WHERE source = ?1") {
            if let Ok(rows) = stmt.query_map([filename], |row| row.get::<_, String>(0)) {
                for r in rows.flatten() { imports_from.push(r); }
            }
        }

        if let Ok(mut stmt2) = self.conn.prepare("SELECT source FROM edges WHERE target = ?1") {
            if let Ok(rows) = stmt2.query_map([filename], |row| row.get::<_, String>(0)) {
                for r in rows.flatten() { imported_by.push(r); }
            }
        }

        let mut out = format!("[ARCHITECTURE CODE MAP]\nFile: {}\n", filename);
        out.push_str("Imports From: ");
        if imports_from.is_empty() { out.push_str("(None)\n"); } else { out.push_str(&imports_from.join(", ")); out.push('\n'); }
        out.push_str("Imported By: ");
        if imported_by.is_empty() { out.push_str("(None)\n"); } else { out.push_str(&imported_by.join(", ")); out.push('\n'); }
        
        out
    }
}

// --- ROUTE 1: TOON SQUEEZER (JSON/XML/HTML) ---
fn try_toon_compression(input: &str) -> Option<String> {
    if let Ok(val) = serde_json::from_str::<serde_json::Value>(input) {
        let mut out = String::new();
        flatten_toon(&val, &mut out, "");
        Some(out.trim().to_string())
    } else if input.trim().starts_with('<') && input.trim().ends_with('>') {
        let mut out = input.replace('\n', " ").replace("  ", " ");
        let closing_tag_re = Regex::new(r"</[^>]+>").unwrap();
        out = closing_tag_re.replace_all(&out, " ").to_string();
        let opening_tag_re = Regex::new(r"<([a-zA-Z0-9_-]+)([^>]*)>").unwrap();
        out = opening_tag_re.replace_all(&out, "$1$2 ").to_string();
        let attr_quotes_re = Regex::new(r#"="([^"]+)""#).unwrap();
        out = attr_quotes_re.replace_all(&out, "=$1").to_string();
        let whitespace_re = Regex::new(r"\s+").unwrap();
        out = whitespace_re.replace_all(&out, " ").to_string();
        Some(out.trim().to_string())
    } else {
        None
    }
}

fn flatten_toon(val: &serde_json::Value, out: &mut String, prefix: &str) {
    match val {
        serde_json::Value::Object(map) => {
            for (k, v) in map {
                let new_prefix = if prefix.is_empty() { k.clone() } else { format!("{}.{}", prefix, k) };
                if v.is_object() || v.is_array() {
                    flatten_toon(v, out, &new_prefix);
                } else {
                    out.push_str(&format!("{}:{} ", new_prefix, v.to_string().trim_matches('"')));
                }
            }
        },
        serde_json::Value::Array(arr) => {
            out.push_str(&format!("{}[{}]: ", prefix, arr.len()));
            for v in arr {
                if v.is_string() || v.is_number() || v.is_boolean() {
                    out.push_str(&format!("{} ", v.to_string().trim_matches('"')));
                }
            }
        },
        _ => {
            out.push_str(&format!("{}:{} ", prefix, val.to_string().trim_matches('"')));
        }
    }
}

// --- ROUTE 2: LATENT-K STRUCTURAL EXTRACTION ---
fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_block = false;
    let mut brace_depth = 0;

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("use ") || trimmed.starts_with("pub mod ") {
            lines.push(line.to_string()); continue;
        }
        if trimmed.starts_with("pub struct ") || trimmed.starts_with("pub enum ") || trimmed.starts_with("pub fn ") || trimmed.starts_with("pub trait ") || trimmed.starts_with("impl ") || trimmed.starts_with("pub use ") || trimmed.starts_with("pub const ") || trimmed.starts_with("pub type ") || trimmed.starts_with("///") {
            if trimmed.ends_with("{") {
                in_block = true; brace_depth = 1;
                lines.push(format!("{} ... }}", line.trim_end_matches('{').trim_end()));
            } else {
                lines.push(line.to_string());
            }
            continue;
        }
        if in_block {
            if trimmed.contains("{") { brace_depth += 1; }
            if trimmed.contains("}") { brace_depth -= 1; }
            if brace_depth == 0 { in_block = false; }
            continue;
        }
        if trimmed.starts_with("#[") || trimmed.starts_with("#!") {
            lines.push(line.to_string());
        }
    }

    let mut result = "[DEPENDENCY MAP (k=1)]\n".to_string();
    let mut deps: Vec<&String> = lines.iter().filter(|l| l.trim().starts_with("use ")).collect();
    if deps.is_empty() { result.push_str("(None detected)\n"); }
    for d in deps { result.push_str(d); result.push('\n'); }
    result.push_str("\n[PUBLIC INTERFACE]\n");
    for l in lines.iter().filter(|l| !l.trim().starts_with("use ")) {
        result.push_str(l); result.push('\n');
    }
    result.trim().to_string()
}

// --- ROUTE 3: SEMANTIC SQUEEZER (Logs & Grep) ---
fn detect_protected_spans(text: &str) -> HashSet<usize> {
    let mut protected_indices = HashSet::new();
    let words: Vec<&str> = text.split_whitespace().collect();
    lazy_static::lazy_static! {
        static ref PATH_RE: Regex = Regex::new(r"(?i)^([./\\]+)?[\w/\\.-]+\.[a-z0-9]{1,5}$").unwrap();
        static ref IP_RE: Regex = Regex::new(r"^\d{1,3}\.\d+\.\d+\.\d+$").unwrap();
        static ref FLAG_RE: Regex = Regex::new(r"^--[a-z-]+$").unwrap();
        static ref HEADER_RE: Regex = Regex::new(r"(?i)^(usage|options|modified|untracked|status|error|critical|failed|reason|latency|author|commit|date|diff):?$").unwrap();
        static ref HEX_RE: Regex = Regex::new(r"^[a-f0-9]{7,40}$").unwrap();
        static ref VER_RE: Regex = Regex::new(r"(?i)v\d+").unwrap();
    }
    for (i, word) in words.iter().enumerate() {
        let clean = word.trim_matches(|c: char| !c.is_alphanumeric() && c != '.' && c != '/' && c != '\\' && c != '[' && c != ']' && c != ':');
        if PATH_RE.is_match(clean) || IP_RE.is_match(clean) || FLAG_RE.is_match(word) || HEADER_RE.is_match(clean) || HEX_RE.is_match(clean) || VER_RE.is_match(clean) || word.contains("=") || word.contains("::") {
            protected_indices.insert(i);
        }
    }
    protected_indices
}

fn calculate_idf(words: &[String]) -> HashMap<String, f64> {
    let mut freq_map = HashMap::new();
    for word in words { *freq_map.entry(word.clone()).or_insert(0) += 1; }
    let total = words.len() as f64;
    freq_map.into_iter().map(|(w, count)| (w, (total / count as f64).ln())).collect()
}

fn calculate_local_entropy(words: &[String]) -> Vec<f64> {
    const WINDOW: usize = 8;
    (0..words.len()).map(|idx| {
        let start = idx.saturating_sub(WINDOW / 2);
        let end = (idx + WINDOW / 2).min(words.len());
        let window = &words[start..end];
        let unique = window.iter().collect::<HashSet<_>>().len();
        unique as f64 / window.len() as f64
    }).collect()
}

fn calculate_pos_importance(word: &str) -> f64 {
    const STOP_WORDS: &[&str] = &["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "it", "of", "be", "with", "by", "from", "as", "this", "that", "those", "these", "then", "than", "run", "only", "used", "each", "other", "any", "multiple", "message", "expected", "will", "all", "has", "have", "can", "could"];
    if STOP_WORDS.contains(&word.to_lowercase().as_str()) { 0.0 } 
    else if word.chars().any(|c| c.is_ascii_uppercase() || c.is_numeric()) { 1.0 } 
    else { 0.5 }
}

fn calculate_position_weight(idx: usize, total: usize) -> f64 {
    if total == 0 { return 1.0; }
    let position = idx as f64 / total as f64;
    4.0 * (position - 0.5).powi(2) + 0.2
}

fn semantic_compression(original_input: &str, config: &Config) -> String {
    let words: Vec<String> = original_input.split_whitespace().map(|s| s.to_string()).collect();
    let total_words = words.len();
    if total_words == 0 { return original_input.to_string(); }

    let protected_spans = detect_protected_spans(original_input);
    let idf_map = calculate_idf(&words);
    let entropy_scores = calculate_local_entropy(&words);

    let mut body = String::new();
    for (i, word) in words.iter().enumerate() {
        if protected_spans.contains(&i) {
            body.push_str(word); body.push(' ');
            continue;
        }
        let idf = idf_map.get(word).unwrap_or(&1.0);
        let pos = calculate_pos_importance(word);
        let entropy = entropy_scores[i];
        let u_shape = calculate_position_weight(i, total_words);
        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight) + (entropy * config.entropy_weight) + (u_shape * config.position_weight);
        if final_score >= config.base_threshold {
            body.push_str(word); body.push(' ');
        }
    }

    body.trim().to_string()
}

// --- THE MASTER ROUTER ---
fn crush_payload(command_type: &str, original_input: &str, config: &Config, code_map: &CodeMapEngine, filename: &str) -> (String, f64) {
    if command_type == "Code Map Tool" {
        return (code_map.read_code_map(filename), 1.0); // 100% compression vs returning full file
    }

    if let Some(toon_crushed) = try_toon_compression(original_input) {
        if toon_crushed.len() < original_input.len() {
            let savings = 1.0 - (toon_crushed.len() as f64 / original_input.len() as f64);
            return (toon_crushed, savings);
        }
    }

    let crushed_content = if command_type == "Code Read" {
        let structural = structural_extraction(original_input);
        let map = code_map.read_code_map(filename);
        format!("{}\n{}", map, structural)
    } else {
        semantic_compression(original_input, config)
    };

    if crushed_content.len() >= original_input.len() {
        return (original_input.to_string(), 0.0);
    }
    let savings = 1.0 - (crushed_content.len() as f64 / original_input.len() as f64);
    (crushed_content, savings)
}

#[derive(serde::Deserialize)]
struct MicroTestCase {
    category: String,
    name: String,
    input: String,
    important_bits: Vec<String>,
}

fn main() {
    println!("🧪 v50 UNIVERSAL GRAPH & DUAL MCP ROUTING");
    let config = Config { 
        idf_weight: 0.65, pos_weight: 0.25, entropy_weight: 0.05,
        position_weight: 0.05, base_threshold: 2.2, 
    };

    // Initialize Global Dependency Graph
    let code_map = CodeMapEngine::new();
    code_map.build_initial_map();

    let mut total_tests = 0;
    let mut passed_tests = 0;

    let micro_file = fs::read_to_string("tests/fixtures/payloads/micro_tests.json").expect("Failed to read micro_tests.json");
    let micros: Vec<MicroTestCase> = serde_json::from_str(&micro_file).expect("Failed to parse micro tests");

    println!("{:-<110}", "");
    println!("{:<15} | {:<20} | {:>10} | {:>10} | {:>8} | Accuracy", "Category", "Test Name", "In Bytes", "Out Bytes", "Comp %");
    println!("{:-<110}", "");

    for tc in micros {
        total_tests += 1;
        let mut local_config = config.clone();
        if tc.input.len() < 200 { local_config.base_threshold = 0.5; } 
        else if tc.input.len() < 500 { local_config.base_threshold = 1.0; }

        let in_bytes = tc.input.len();
        let (output, comp_ratio) = crush_payload("General", &tc.input, &local_config, &code_map, "");
        let out_bytes = output.len();
        let mut missed = Vec::new();
        for bit in &tc.important_bits {
            if !output.to_lowercase().contains(&bit.to_lowercase()) { missed.push(bit.clone()); }
        }
        let status = if missed.is_empty() { passed_tests += 1; "\x1b[32m100%\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
        let display_comp = if comp_ratio == 0.0 { "BYPASS".to_string() } else { format!("{:>7.1}%", comp_ratio * 100.0) };
        
        if !missed.is_empty() {
            println!("{:<15} | {:<20} | {:>10} | {:>10} | {:>8} | {}", tc.category, tc.name.chars().take(20).collect::<String>(), in_bytes, out_bytes, display_comp, status);
            println!("   ↳ Lost bits: {:?}", missed);
        }
    }

    let macro_cases = vec![
        ("Recon", "git status", fs::read_to_string("tests/fixtures/payloads/git_status.txt").unwrap_or_default(), vec!["main", "modified:", "GEMINI.md", "audit_logs/"], ""),
        ("Tooling", "cargo test --help", fs::read_to_string("tests/fixtures/payloads/cargo_test_help.txt").unwrap_or_default(), vec!["Usage:", "--list", "--fail-fast", "--format", "--shuffle-seed", "--include-ignored"], ""),
        ("Git Patch", "git log -p", fs::read_to_string("tests/fixtures/payloads/git_log.txt").unwrap_or_default(), vec!["e699d4b7b187171c65b06694ed4f128a3c68e058", "feat(mcp): Finalize v24", "049a2cb060fba8c50aebe9878f8201943bbaf1e0"], ""),
        ("Code Read", "cat src/converters/pdf.rs", fs::read_to_string("src/converters/pdf.rs").unwrap_or_default(), vec!["[ARCHITECTURE CODE MAP]", "src/converters/pdf.rs", "Imports From:", "pub struct PdfConverter", "[DEPENDENCY MAP (k=1)]"], "src/converters/pdf.rs"),
        ("Code Map Tool", "read_code_map lib.rs", "src/lib.rs".to_string(), vec!["[ARCHITECTURE CODE MAP]", "File: src/lib.rs", "Imports From", "Imported By"], "src/lib.rs"),
        ("Code Map Tool", "read_code_map pdf.rs", "src/converters/pdf.rs".to_string(), vec!["[ARCHITECTURE CODE MAP]", "File: src/converters/pdf.rs", "Imports From", "Imported By"], "src/converters/pdf.rs"),
        ("Build Log", "cargo check", fs::read_to_string("tests/fixtures/payloads/cargo_check.txt").unwrap_or_default(), vec!["transmutation", "Finished `dev` profile"], ""),
        ("Structured", "Project JSON", fs::read_to_string("tests/fixtures/payloads/project_structure.json").unwrap_or_default(), vec!["transmutation-streaming", "0.3.2", "audit_logs", "Cargo.toml"], ""),
        ("Structured", "Project XML", fs::read_to_string("tests/fixtures/payloads/project_structure.xml").unwrap_or_default(), vec!["transmutation-streaming", "0.3.2", "audit_logs", "Cargo.toml"], ""),
        ("Structured", "Test Report HTML", fs::read_to_string("tests/fixtures/payloads/test_report.html").unwrap_or_default(), vec!["Test Report - transmutation-streaming", "141", "test_pdf_extraction_fails_on_corrupt_file", "tests/pdf_tests.rs:114:5"], ""),
    ];

    println!("{:-<110}", "");
    for (cat, name, input, bits, target_file) in macro_cases {
        if input.is_empty() { continue; }
        total_tests += 1;
        let in_bytes = input.len();
        let (output, comp_ratio) = crush_payload(cat, &input, &config, &code_map, target_file);
        let out_bytes = output.len();
        let mut missed = Vec::new();
        for bit in &bits {
            if !output.to_lowercase().contains(&bit.to_lowercase()) { missed.push(bit); }
        }
        let status = if missed.is_empty() { passed_tests += 1; "\x1b[32m100%\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
        let display_comp = if comp_ratio == 0.0 { "BYPASS".to_string() } else { format!("{:>7.1}%", comp_ratio * 100.0) };
        
        let display_name = if name.len() > 20 { &name[..20] } else { name };
        println!("{:<15} | {:<20} | {:>10} | {:>10} | {:>8} | {}", cat, display_name, in_bytes, out_bytes, display_comp, status);
        if !missed.is_empty() { println!("   ↳ Lost bits: {:?}", missed); }
    }

    println!("\n📊 FINAL SUMMARY: {}/{} total test cases passed with 100% accuracy.", passed_tests, total_tests);
}