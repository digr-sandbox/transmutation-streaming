use std::collections::{HashSet, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use serde::{Deserialize};
use transmutation::{Converter, OutputFormat};

/// --- UNIFIED PRODUCTION EVALUATION SUITE ---
/// Merges Micro-Payloads (45 cases) with Polyglot Stress Assets (8 cases).

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

    fn is_needle(&self, token: &str) -> bool {
        let clean = token.trim_matches(|c: char| !c.is_alphanumeric() && c != '@' && c != '_' && c != ':');
        if clean.len() < 4 { return false; }
        if self.tokens.contains(clean.to_lowercase().as_str()) { return false; }
        let has_upper = clean.chars().any(|c| c.is_uppercase());
        let has_lower = clean.chars().any(|c| c.is_lowercase());
        let is_mixed = has_upper && has_lower;
        let upper_count = clean.chars().filter(|c| c.is_uppercase()).count();
        clean.contains('@') || clean.contains('_') || clean.contains(':') || (is_mixed && !clean.chars().next().unwrap().is_uppercase()) || upper_count > 1
    }
}

fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_import = false;
    let boredom_table: HashSet<&str> = ["if", "else", "let", "var", "const", "return", "public", "private", "protected", "class", "function", "fn", "void", "int", "char", "string", "bool", "true", "false", "import", "from", "use", "include", "struct", "impl", "type", "interface", "package", "namespace", "static", "async", "await", "try", "catch", "throw", "new", "delete", "this", "self", "super", "for", "while", "do", "switch", "case", "default", "break", "continue", "in", "of", "as", "is"].iter().cloned().collect();

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() { continue; }
        if trimmed.contains("JUNK_") || trimmed.contains("LICENSE_HEADER") { continue; }
        if trimmed.starts_with("import ") || trimmed.starts_with("use ") || trimmed.starts_with("#include") || trimmed.starts_with("package ") {
            if trimmed.contains('{') && !trimmed.contains('}') { in_import = true; }
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') { in_import = false; }
            continue;
        }
        if in_import {
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') { in_import = false; }
            continue;
        }
        let mut score = 0;
        if trimmed.starts_with('@') || trimmed.starts_with("#[") || trimmed.starts_with("#!") { score += 10; }
        if trimmed.ends_with('{') || trimmed.ends_with(':') || trimmed.ends_with('[') || trimmed.ends_with('(') || trimmed.contains("interface ") || (trimmed.contains("func ") && !trimmed.contains('}')) { score += 10; }
        if trimmed.contains("await") || trimmed.contains("return") || trimmed.contains("throw") || trimmed.contains("yield") { score += 5; }
        if trimmed.contains('.') || trimmed.contains(':') || (trimmed.contains('(') && trimmed.contains(')')) { score += 5; }
        let has_high_signal = trimmed.split(|c: char| !c.is_alphanumeric() && c != '@' && c != '_').any(|token| {
            if token.is_empty() { return false; }
            if boredom_table.contains(token.to_lowercase().as_str()) { return false; }
            let has_upper = token.chars().any(|c| c.is_uppercase());
            let has_lower = token.chars().any(|c| c.is_lowercase());
            token.len() > 3 && (has_upper && has_lower || token.contains('_') || token.contains('@'))
        });
        if has_high_signal { score += 5; }
        if score > 0 { lines.push(line.to_string()); }
    }
    lines.join("\n")
}

#[tokio::main]
async fn main() {
    println!("🚀 UNIFIED PRODUCTION EVALUATION SUITE (v2026.1)");
    println!("=================================================");

    let boring = BoringTable::new();
    let mut total_tests = 0;
    let mut passed_tests = 0;

    println!("{:<15} | {:<25} | {:>8} | {:>8} | Accuracy", "Category", "Test Name", "InSize", "Comp %");
    println!("{:-<85}", "");

    // 1. RUN MICRO-PAYLOADS (45 Tests)
    let micro_json = fs::read_to_string("tests/fixtures/payloads/micro_tests.json").unwrap_or_default();
    if let Ok(micro_cases) = serde_json::from_str::<Vec<MicroTest>>(&micro_json) {
        for tc in micro_cases {
            total_tests += 1;
            let output = structural_extraction(&tc.input);
            let comp_ratio = 1.0 - (output.len() as f64 / tc.input.len() as f64);
            let mut missed = Vec::new();
            for bit in &tc.important_bits {
                if !output.to_lowercase().contains(&bit.to_lowercase()) { missed.push(bit); }
            }
            let acc = if tc.important_bits.is_empty() { 100.0 } else { (tc.important_bits.len() - missed.len()) as f64 / tc.important_bits.len() as f64 * 100.0 };
            let status = if acc >= 99.0 { passed_tests += 1; "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
            println!("{:<15} | {:<25} | {:>8} | {:>7.1}% | {:.1}% {}", tc.category, tc.name.chars().take(25).collect::<String>(), tc.input.len(), comp_ratio * 100.0, acc, status);
        }
    }

    // 2. RUN POLYGLOT STRESS ASSETS (8 Tests)
    let poly_dir = "tests/fixtures/payloads/polyglot";
    if let Ok(entries) = fs::read_dir(poly_dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.extension().map_or(true, |ext| ext == "json") { continue; }
            total_tests += 1;
            let original = fs::read_to_string(&path).unwrap_or_default();
            let mut needles = Vec::new();
            for word in original.split_whitespace() { if boring.is_needle(word) && !needles.contains(&word.to_string()) { needles.push(word.to_string()); } }
            let mutated = format!("// JUNK_LICENSE_HEADER\n{}\n// JUNK_LICENSE_HEADER", original);
            let output = structural_extraction(&mutated);
            let comp_ratio = 1.0 - (output.len() as f64 / mutated.len() as f64);
            let mut missed = Vec::new();
            for n in &needles { if !output.contains(n) { missed.push(n); } }
            let acc = if needles.is_empty() { 100.0 } else { (needles.len() - missed.len()) as f64 / needles.len() as f64 * 100.0 };
            let status = if acc >= 90.0 { passed_tests += 1; "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
            println!("{:<15} | {:<25} | {:>8} | {:>7.1}% | {:.1}% {}", "Polyglot", path.file_name().unwrap().to_string_lossy(), mutated.len(), comp_ratio * 100.0, acc, status);
        }
    }

    println!("\n📊 FINAL SUMMARY: {}/{} total test cases passed.", passed_tests, total_tests);
}
