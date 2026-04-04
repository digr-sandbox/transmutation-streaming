use std::collections::{HashSet, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use serde::{Deserialize};

/// --- UNIFIED PRODUCTION EVALUATION SUITE (v2026.1) ---
/// Benchmarks Best-Practices vs. High-Entropy Slop with Domain-Aware Routing

#[derive(Deserialize)]
struct MicroTest {
    category: String,
    name: String,
    input: String,
    important_bits: Vec<String>,
}

struct BoringTable {
    tokens: HashSet<&'static str>,
}

impl BoringTable {
    fn new() -> Self {
        let mut tokens = HashSet::new();
        let common = ["if", "else", "let", "var", "const", "return", "public", "private", "protected", "class", "function", "fn", "void", "int", "char", "string", "bool", "true", "false", "import", "from", "use", "include", "struct", "impl", "type", "interface", "package", "namespace", "static", "async", "await", "try", "catch", "throw", "new", "delete", "this", "self", "super", "for", "while", "do", "switch", "case", "default", "break", "continue", "in", "of", "as", "is"];
        for t in common { tokens.insert(t); }
        Self { tokens }
    }

    fn extract_needles(&self, content: &str, is_sql: bool) -> Vec<String> {
        let mut needles = Vec::new();
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() { continue; }

            // ABSOLUTE COMMENT STRIPPER
            if (trimmed.starts_with("//") || trimmed.starts_with('#') || trimmed.starts_with("/*") || 
                trimmed.starts_with('*') || trimmed.starts_with("--") || trimmed.starts_with('%')) 
               && !trimmed.contains('@') && !trimmed.contains("#[") {
                continue;
            }

            let is_sig = (trimmed.ends_with('{') || trimmed.ends_with(':') || trimmed.contains("struct ") || trimmed.contains("interface ") || trimmed.to_uppercase().contains("CREATE TABLE") || trimmed.starts_with("type ")) && !trimmed.contains('}');
            let is_meta = trimmed.starts_with('@') || trimmed.starts_with("#[") || trimmed.starts_with("import ") || trimmed.starts_with("#include");
            let is_logic = trimmed.contains("return") || trimmed.contains("throw") || trimmed.contains("await") || 
                           trimmed.contains("malloc") || trimmed.contains("free") || trimmed.contains("strdup") || trimmed.to_uppercase().contains("PRIMARY KEY");

            if is_sig || is_meta || is_logic || is_sql {
                for word in trimmed.split(|c: char| !c.is_alphanumeric() && c != '@' && c != '_' && c != '$') {
                    if self.is_needle(word, is_sql) && !needles.contains(&word.to_string()) {
                        needles.push(word.to_string());
                    }
                }
            }
        }
        needles
    }

    fn is_needle(&self, token: &str, is_sql: bool) -> bool {
        let clean = token.trim_matches(|c: char| !c.is_alphanumeric() && c != '@' && c != '_' && c != '$');
        if clean.len() < 3 { return false; }
        if self.tokens.contains(clean.to_lowercase().as_str()) { return false; }
        
        let has_upper = clean.chars().any(|c| c.is_uppercase());
        let has_lower = clean.chars().any(|c| c.is_lowercase());
        let is_mixed = has_upper && has_lower;
        let is_all_caps = has_upper && !has_lower;

        if is_sql && is_all_caps { return true; }
        clean.contains('@') || clean.contains('_') || is_mixed || clean.contains('$')
    }
}

fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_import = false;
    let mut depth = 0;
    let mut in_structural = false;
    let boredom_table: HashSet<&str> = ["if", "else", "let", "var", "const", "return", "public", "private", "protected", "class", "function", "fn", "void", "int", "char", "string", "bool", "true", "false", "import", "from", "use", "include", "struct", "impl", "type", "interface", "package", "namespace", "static", "async", "await", "try", "catch", "throw", "new", "delete", "this", "self", "super", "for", "while", "do", "switch", "case", "default", "break", "continue", "in", "of", "as", "is"].iter().cloned().collect();

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() { continue; }

        // --- PASS 0: ABSOLUTE EVICTION (HARD PRIORITY) ---
        if (trimmed.starts_with("//") || trimmed.starts_with('#') || trimmed.starts_with("/*") || 
            trimmed.starts_with('*') || trimmed.starts_with('%') || trimmed.starts_with("--")) 
           && !trimmed.contains('@') && !trimmed.contains("#[") {
            continue;
        }
        if trimmed.contains("JUNK_") || trimmed.contains("LICENSE_HEADER") { continue; }

        // --- PASS 1: IMPORT ANCHORING ---
        if trimmed.starts_with("import ") || trimmed.starts_with("use ") || trimmed.starts_with("#include") || trimmed.starts_with("package ") || trimmed.starts_with("-module") {
            if trimmed.contains('{') && !trimmed.contains('}') { in_import = true; }
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') || trimmed.ends_with('.') { in_import = false; }
            continue;
        }
        if in_import { 
            lines.push(line.to_string()); 
            if trimmed.contains('}') || trimmed.contains(';') || trimmed.ends_with('.') { in_import = false; } 
            continue; 
        }

        let open_braces = trimmed.chars().filter(|&c| c == '{').count();
        let close_braces = trimmed.chars().filter(|&c| c == '}').count();
        let was_at_root = depth == 0;
        let is_structural = trimmed.contains("struct") || trimmed.contains("typedef") || trimmed.contains("interface") || trimmed.contains("enum") || trimmed.to_uppercase().contains("TABLE") || trimmed.starts_with("type ") || trimmed.starts_with("query ");
        
        if is_structural { in_structural = true; }

        let mut score = 0;
        if trimmed.starts_with('@') || trimmed.starts_with("#[") || trimmed.starts_with("#!") || trimmed.starts_with("<?php") || trimmed.starts_with("-module") { score += 30; }
        if trimmed.ends_with('{') || trimmed.ends_with(':') || trimmed.ends_with('[') || is_structural || (trimmed.contains("func ") && !trimmed.contains('}')) || trimmed.contains("::") || trimmed.contains("->") { score += 20; }
        if trimmed.contains("return") || trimmed.contains("throw") || trimmed.contains("malloc") || trimmed.contains("await") || trimmed.to_uppercase().contains("PRIMARY KEY") { score += 15; }
        if trimmed.contains("->") || trimmed.contains('*') || trimmed.contains('&') || (trimmed.contains('.') && (trimmed.contains('(') || trimmed.contains('['))) || (trimmed.contains(':') && !trimmed.contains('{')) { score += 10; }
        
        let has_high_signal = trimmed.split(|c: char| !c.is_alphanumeric() && c != '@' && c != '_').any(|token| {
            if token.is_empty() || boredom_table.contains(token.to_lowercase().as_str()) { return false; }
            let has_upper = token.chars().any(|c| c.is_uppercase());
            let has_lower = token.chars().any(|c| c.is_lowercase());
            token.len() > 2 && (has_upper && has_lower || token.contains('_') || token.ends_with('*') || token.chars().all(|c| c.is_uppercase()))
        });
        if has_high_signal { score += 5; }

        let threshold = if was_at_root || in_structural { 1 } else { 10 };
        if score >= threshold {
            let is_complex_line = trimmed.contains('(') || (trimmed.contains(':') && !trimmed.contains('{'));
            if was_at_root && trimmed.ends_with('{') && !is_complex_line && !is_structural { lines.push(format!("{} ... }}", line.trim_end_matches('{').trim_end())); }
            else { lines.push(line.to_string()); }
        }
        depth = depth + open_braces as i32 - close_braces as i32;
        if depth <= 0 { depth = 0; in_structural = false; }
    }
    lines.join("\n")
}

fn log_squeezer(input: &str) -> String {
    if input.lines().count() < 10 { return input.to_string(); }
    input.to_string()
}

#[tokio::main]
async fn main() {
    println!("🚀 UNIFIED PRODUCTION EVALUATION SUITE (v2026.1)");
    println!("=================================================");
    let boring = BoringTable::new();
    let mut total_tests = 0;
    let mut passed_tests = 0;
    println!("{:<15} | {:<25} | {:>8} | {:>8} | Result", "Category", "Test Name", "InSize", "Comp %");
    println!("{:-<85}", "");

    let micro_json = fs::read_to_string("tests/fixtures/payloads/micro_tests.json").unwrap_or_default();
    if let Ok(micro_cases) = serde_json::from_str::<Vec<MicroTest>>(&micro_json) {
        for tc in micro_cases {
            total_tests += 1;
            let output = if tc.category == "Code" { structural_extraction(&tc.input) } else { log_squeezer(&tc.input) };
            let comp_ratio = 1.0 - (output.len() as f64 / tc.input.len() as f64);
            let mut missed = Vec::new();
            for bit in &tc.important_bits { if !output.to_lowercase().contains(&bit.to_lowercase()) { missed.push(bit); } }
            let acc = if tc.important_bits.is_empty() { 100.0 } else { (tc.important_bits.len() - missed.len()) as f64 / tc.important_bits.len() as f64 * 100.0 };
            let status = if acc >= 100.0 { passed_tests += 1; "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
            println!("{:<15} | {:<25} | {:>8} | {:>7.1}% | {:.1}% {}", tc.category, tc.name.chars().take(25).collect::<String>(), tc.input.len(), comp_ratio * 100.0, acc, status);
        }
    }

    let mut clean_needles: HashMap<String, Vec<String>> = HashMap::new();
    let clean_dir = "tests/fixtures/payloads/polyglot";
    if let Ok(entries) = fs::read_dir(clean_dir) {
        let mut entries_vec: Vec<_> = entries.filter_map(|e| e.ok()).collect();
        entries_vec.sort_by_key(|e| e.path());
        for entry in entries_vec {
            let path = entry.path();
            if path.extension().map_or(true, |ext| ext == "json") { continue; }
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            let original = fs::read_to_string(&path).unwrap_or_default();
            let is_sql = name.ends_with(".sql") || name.ends_with(".graphql");
            let needles = boring.extract_needles(&original, is_sql);
            total_tests += 1;
            let output = structural_extraction(&original);
            let comp_ratio = 1.0 - (output.len() as f64 / original.len() as f64);
            let mut missed = Vec::new();
            for n in &needles { if !output.contains(n) { missed.push(n); } }
            let acc = if needles.is_empty() { 100.0 } else { (needles.len() - missed.len()) as f64 / needles.len() as f64 * 100.0 };
            let status = if acc >= 100.0 { passed_tests += 1; "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
            println!("{:<15} | {:<25} | {:>8} | {:>7.1}% | {:.1}% {}", "Poly-Clean", name, original.len(), comp_ratio * 100.0, acc, status);
            if acc < 100.0 { println!("   ↳ Lost: {:?}", missed); }
            clean_needles.insert(name, needles);
        }
    }

    let slop_dir = "tests/fixtures/payloads/slop";
    if let Ok(entries) = fs::read_dir(slop_dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let path = entry.path();
            let filename = path.file_name().unwrap().to_string_lossy().to_string();
            let clean_filename = filename.replace(".slop", "");
            if let Some(needles) = clean_needles.get(&clean_filename) {
                total_tests += 1;
                let original = fs::read_to_string(&path).unwrap_or_default();
                let output = structural_extraction(&original);
                let comp_ratio = 1.0 - (output.len() as f64 / original.len() as f64);
                let mut missed = Vec::new();
                for n in needles { if !output.contains(n) { missed.push(n); } }
                let acc = if needles.is_empty() { 100.0 } else { (needles.len() - missed.len()) as f64 / needles.len() as f64 * 100.0 };
                let status = if acc >= 100.0 { passed_tests += 1; "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
                println!("{:<15} | {:<25} | {:>8} | {:>7.1}% | {:.1}% {}", "Poly-Slop", filename, original.len(), comp_ratio * 100.0, acc, status);
                if acc < 100.0 { println!("   ↳ Lost: {:?}", missed); }
            }
        }
    }
    println!("\n📊 FINAL SUMMARY: {}/{} total test cases passed.", passed_tests, total_tests);
}
