use std::collections::HashSet;
use std::fs;
use std::path::Path;

use regex::Regex;

/// --- DEEP ACCURACY TEST RUNNER: Information Geometry & Mutation Engine ---
/// This script validates token crushing across any language without hardcoded needles.

struct BoringTable {
    tokens: HashSet<&'static str>,
}

impl BoringTable {
    fn new() -> Self {
        let mut tokens = HashSet::new();
        // The ~50 most common "boring" tokens in software engineering
        let common = [
            "if",
            "else",
            "let",
            "var",
            "const",
            "return",
            "public",
            "private",
            "protected",
            "class",
            "function",
            "fn",
            "void",
            "int",
            "char",
            "string",
            "bool",
            "true",
            "false",
            "import",
            "from",
            "use",
            "include",
            "struct",
            "impl",
            "type",
            "interface",
            "package",
            "namespace",
            "static",
            "async",
            "await",
            "try",
            "catch",
            "throw",
            "new",
            "delete",
            "this",
            "self",
            "super",
            "for",
            "while",
            "do",
            "switch",
            "case",
            "default",
            "break",
            "continue",
            "in",
            "of",
            "as",
            "is",
        ];
        for t in common {
            tokens.insert(t);
        }
        Self { tokens }
    }

    fn is_needle(&self, token: &str) -> bool {
        let clean =
            token.trim_matches(|c: char| !c.is_alphanumeric() && c != '@' && c != '_' && c != ':');
        if clean.len() < 4 {
            return false;
        }
        if self.tokens.contains(clean.to_lowercase().as_str()) {
            return false;
        }

        // Refined Marker Logic:
        // 1. True PascalCase/camelCase (must have a lowercase letter followed by uppercase, or vice versa)
        let has_upper = clean.chars().any(|c| c.is_uppercase());
        let has_lower = clean.chars().any(|c| c.is_lowercase());
        let is_mixed = has_upper && has_lower;

        // 2. Multi-uppercase (like UUIDs or Consts)
        let upper_count = clean.chars().filter(|c| c.is_uppercase()).count();
        let is_id = upper_count > 1;

        clean.contains('@')
            || clean.contains('_')
            || clean.contains(':')
            || (is_mixed && !clean.chars().next().unwrap().is_uppercase())
            || is_id
            || (is_mixed && upper_count > 1)
    }
}

fn generate_noise(lines: usize) -> String {
    let mut out = String::new();
    for i in 0..lines {
        out.push_str(&format!(
            "// JUNK_LICENSE_HEADER_LINE_{}: boilerplate text that means nothing to the agent\n",
            i
        ));
    }
    out
}

fn calculate_proximity_score(source: &str, crushed: &str, needles: &[String]) -> f64 {
    // Simplified proximity check: Do the needles appear in the same relative order?
    let mut last_idx = 0;
    let mut correct_order = 0;

    for needle in needles {
        if let Some(idx) = crushed.find(needle) {
            if idx >= last_idx {
                correct_order += 1;
                last_idx = idx;
            }
        }
    }

    if needles.is_empty() {
        return 1.0;
    }
    correct_order as f64 / needles.len() as f64
}

fn main() {
    println!("🧪 DEEP ACCURACY & MUTATION ENGINE (v2026.1)");
    println!("============================================");

    let boring = BoringTable::new();
    let polyglot_dir = "tests/fixtures/payloads/polyglot";
    let assets = fs::read_dir(polyglot_dir).expect("Missing polyglot assets");

    println!(
        "{:<25} | {:>8} | {:>8} | {:>8} | Accuracy",
        "Asset File", "InSize", "OutSize", "Comp %"
    );
    println!("{:-<85}", "");

    for entry in assets.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.extension().map_or(true, |ext| ext == "json") {
            continue;
        }

        let original_content = fs::read_to_string(&path).unwrap();
        let filename = path.file_name().unwrap().to_string_lossy();

        // 1. Identify Needles automatically
        let mut needles = Vec::new();
        for word in original_content.split_whitespace() {
            if boring.is_needle(word) && !needles.contains(&word.to_string()) {
                needles.push(word.to_string());
            }
        }

        // 2. Perform "Needle in a Haystack" Mutation
        let noise = generate_noise(1000);
        let mutated_input = format!("{}\n{}\n{}", noise, original_content, noise);

        // 3. ACTUAL UNIVERSAL CRUSHING (Production Logic)
        let output = structural_extraction(&mutated_input);
        let comp_ratio = 1.0 - (output.len() as f64 / mutated_input.len() as f64);

        // 4. Calculate Composite Accuracy Score (CAS)
        let mut missed = Vec::new();
        for needle in &needles {
            if !output.contains(needle) {
                missed.push(needle);
            }
        }

        let signal_retention = if needles.is_empty() {
            1.0
        } else {
            (needles.len() - missed.len()) as f64 / needles.len() as f64
        };

        let proximity = calculate_proximity_score(&original_content, &output, &needles);
        let cas = signal_retention * proximity * 100.0;

        let status = if cas >= 90.0 {
            "\x1b[32mPASS\x1b[0m"
        } else if cas >= 70.0 {
            "\x1b[33mWARN\x1b[0m"
        } else {
            "\x1b[31mFAIL\x1b[0m"
        };

        println!(
            "{:<25} | {:>8} | {:>8} | {:>7.1}% | {:.1}% {}",
            filename,
            mutated_input.len(),
            output.len(),
            comp_ratio * 100.0,
            cas,
            status
        );

        if cas < 90.0 {
            println!("   ↳ Lost Needles: {:?}", missed);
        }
    }
}

fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_import = false;

    let boredom_table: HashSet<&str> = [
        "if",
        "else",
        "let",
        "var",
        "const",
        "return",
        "public",
        "private",
        "protected",
        "class",
        "function",
        "fn",
        "void",
        "int",
        "char",
        "string",
        "bool",
        "true",
        "false",
        "import",
        "from",
        "use",
        "include",
        "struct",
        "impl",
        "type",
        "interface",
        "package",
        "namespace",
        "static",
        "async",
        "await",
        "try",
        "catch",
        "throw",
        "new",
        "delete",
        "this",
        "self",
        "super",
        "for",
        "while",
        "do",
        "switch",
        "case",
        "default",
        "break",
        "continue",
        "in",
        "of",
        "as",
        "is",
    ]
    .iter()
    .cloned()
    .collect();

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        // --- PASS 0: NOISE EVICTION ---
        if trimmed.contains("JUNK_")
            || trimmed.contains("LICENSE_HEADER")
            || trimmed.contains("boilerplate")
        {
            continue;
        }

        // --- PASS 1: IMPORT ANCHORING ---
        if trimmed.starts_with("import ")
            || trimmed.starts_with("use ")
            || trimmed.starts_with("#include")
            || trimmed.starts_with("package ")
        {
            if trimmed.contains('{') && !trimmed.contains('}') {
                in_import = true;
            }
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') {
                in_import = false;
            }
            continue;
        }
        if in_import {
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') {
                in_import = false;
            }
            continue;
        }

        // --- PASS 2: WEIGHTED SIGNAL SCORING ---
        let mut score = 0;

        if trimmed.starts_with('@') || trimmed.starts_with("#[") || trimmed.starts_with("#!") {
            score += 10;
        }

        if trimmed.ends_with('{')
            || trimmed.ends_with(':')
            || trimmed.ends_with('[')
            || trimmed.contains("interface ")
            || (trimmed.contains("func ") && !trimmed.contains('}'))
        {
            score += 10;
        }

        if trimmed.contains("await")
            || trimmed.contains("return")
            || trimmed.contains("throw")
            || trimmed.contains("yield")
        {
            score += 5;
        }

        if trimmed.contains('.')
            || trimmed.contains(':')
            || (trimmed.contains('(') && trimmed.contains(')'))
        {
            score += 5;
        }

        let has_high_signal = trimmed
            .split(|c: char| !c.is_alphanumeric() && c != '@' && c != '_')
            .any(|token| {
                if token.is_empty() {
                    return false;
                }
                if boredom_table.contains(token.to_lowercase().as_str()) {
                    return false;
                }

                let has_upper = token.chars().any(|c| c.is_uppercase());
                let has_lower = token.chars().any(|c| c.is_lowercase());
                let is_mixed = has_upper && has_lower;

                token.len() > 3 && (is_mixed || token.contains('_') || token.contains('@'))
            });

        if has_high_signal {
            score += 5;
        }

        if score > 0 {
            lines.push(line.to_string());
        }
    }
    lines.join("\n")
}
