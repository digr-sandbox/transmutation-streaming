use std::collections::{HashMap, HashSet};
use regex::Regex;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use std::fs;
use std::path::PathBuf;
use sysinfo::System;
use rusqlite::{params, Connection};
use std::time::Instant;

/// --- THE PRUNING SUITE: v15 Precision Squeeze Engine ---

#[derive(Clone)]
struct Config {
    idf_weight: f64,
    pos_weight: f64,
    entropy_weight: f64,
    base_threshold: f64,
}

struct WordAudit {
    text: String,
    final_score: f64,
    kept: bool,
}

fn apply_toon(text: &str, category: &str) -> (String, usize) {
    let mut result = text.to_string();
    if category == "JSON" {
        let json_key_re = Regex::new(r#""(\w+)":\s*"#).unwrap();
        result = json_key_re.replace_all(&result, "$1: ").to_string();
    }
    let ws_re = Regex::new(r"\s{2,}").unwrap();
    result = ws_re.replace_all(&result, " ").to_string();
    let saved = text.len().saturating_sub(result.len());
    (result, saved)
}

fn is_protected(word: &str) -> bool {
    lazy_static::lazy_static! {
        static ref IP_RE: Regex = Regex::new(r"^\d{1,3}\.\d+\.\d+\.\d+$").unwrap();
        static ref PATH_RE: Regex = Regex::new(r"(?i)^[/\\]?[\w/\\.-]+\.[a-z0-9]{1,5}$").unwrap();
        static ref METRIC_RE: Regex = Regex::new(r"^\d+(ms|s|m|h)$").unwrap();
        static ref SEMANTIC_RE: Regex = Regex::new(r"(?i)^(error|fail|panic|exception|fatal|warn|critical|debug|unresolved|timeout|refused|denied|abort|success|successfully|done|finished|status|login|node|pod|impl|async|fn|result|ok|select|insert|update|join|where|group|by|order|limit|begin|commit)$").unwrap();
    }
    let clean = word.trim_matches(|c: char| !c.is_alphanumeric() && c != '.' && c != '/');
    IP_RE.is_match(clean) || PATH_RE.is_match(clean) || METRIC_RE.is_match(clean) || SEMANTIC_RE.is_match(clean)
}

/// Feature: Dynamic Lexicon Generation (v15)
fn generate_lexicon(words: &[String]) -> (HashMap<String, String>, String, usize) {
    let mut freq = HashMap::new();
    for w in words { if w.len() > 6 { *freq.entry(w.clone()).or_insert(0) += 1; } }
    
    let mut legend_map = HashMap::new();
    let mut legend_str = String::new();
    let mut savings = 0;
    let mut alias_idx = 'a';

    for (word, count) in freq {
        if count > 2 { // Repeat threshold
            let alias = format!("@{}", alias_idx);
            legend_map.insert(word.clone(), alias.clone());
            legend_str.push_str(&format!("{}:\"{}\" ", alias, word));
            savings += (word.len() - alias.len()) * count;
            alias_idx = ((alias_idx as u8) + 1) as char;
            if alias_idx > 'z' { break; }
        }
    }
    (legend_map, legend_str.trim().to_string(), savings)
}

fn run_suite(words: &[String], config: &Config, category: &str) -> Vec<WordAudit> {
    let mut freq_map = HashMap::new();
    for w in words { *freq_map.entry(w).or_insert(0) += 1; }
    let total = words.len() as f64;

    let mut audits = Vec::new();
    const WINDOW: usize = 10;

    for (idx, word) in words.iter().enumerate() {
        if is_protected(word) {
            audits.push(WordAudit { text: word.clone(), final_score: f64::INFINITY, kept: true });
            continue;
        }

        let count = freq_map.get(word).unwrap_or(&1);
        let idf = (total / *count as f64).ln();
        
        let stop_words: HashSet<&str> = ["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "it", "this", "of", "be"].into_iter().collect();
        let pos = if stop_words.contains(word.to_lowercase().as_str()) { 0.05 } else { 0.80 };

        let start = idx.saturating_sub(WINDOW / 2);
        let end = (idx + WINDOW / 2).min(words.len());
        let window = &words[start..end];
        let unique = window.iter().collect::<HashSet<_>>().len();
        let entropy = unique as f64 / window.len() as f64;

        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight) + (entropy * config.entropy_weight);
        
        // ADAPTIVE THRESHOLD (v15): Lower threshold if high entropy (Likely Signal)
        let threshold = if entropy > 0.8 { config.base_threshold * 0.7 } else { config.base_threshold };
        
        audits.push(WordAudit { text: word.clone(), final_score, kept: final_score >= threshold });
    }
    audits
}

struct TestCase {
    category: &'static str,
    name: &'static str,
    input: String,
    important_bits: Vec<&'static str>,
}

fn get_test_cases() -> Vec<TestCase> {
    vec![
        TestCase {
            category: "Build Logs",
            name: "NPM Success",
            input: "npm info it worked. npm info using npm@10.2.4. webpack compiled successfully in 1243ms. output saved to ./dist/main.js".to_string(),
            important_bits: vec!["successfully", "1243ms", "./dist/main.js"],
        },
        TestCase {
            category: "Server Logs",
            name: "Duplicate Burst",
            input: "info: request processed. info: request processed. info: request processed. info: request processed. error: connection reset.".to_string(),
            important_bits: vec!["processed", "reset"],
        },
        TestCase {
            category: "JSON",
            name: "Cloud Config",
            input: r#"{"status": "success", "data": {"id": "i-0987654321", "type": "t3.medium", "region": "us-east-1", "tags": {"environment": "production"}}}"#.to_string(),
            important_bits: vec!["i-0987654321", "t3.medium", "production"],
        },
    ]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let test_cases = get_test_cases();
    let config = Config { idf_weight: 0.25, pos_weight: 0.55, entropy_weight: 0.20, base_threshold: 1.2 };

    let db_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap();
    let db_path = db_dir.join("audit.db");
    let mut conn = Connection::open(&db_path)?;

    println!("🧪 v15 PRECISION SQUEEZE: 99% ACCURACY TARGET");
    println!("================================================================================\n");

    for tc in test_cases {
        let start_time = Instant::now();
        let (toon_text, _toon_saved) = apply_toon(&tc.input, tc.category);
        let raw_words: Vec<String> = toon_text.split_whitespace().map(|s| s.to_string()).collect();
        
        // 1. Lexicon Pass (v15)
        let (legend_map, legend_str, _lex_saved) = generate_lexicon(&raw_words);
        let mut aliased_words = Vec::new();
        for w in raw_words { aliased_words.push(legend_map.get(&w).cloned().unwrap_or(w)); }

        // 2. Pruning Pass
        let result = run_suite(&aliased_words, &config, tc.category);
        let mut kept_text = String::new();
        if !legend_str.is_empty() { kept_text.push_str(&format!("LEGEND: {} | ", legend_str)); }
        for r in &result { if r.kept { kept_text.push_str(&r.text); kept_text.push(' '); } }
        
        let duration = start_time.elapsed();

        // 3. Shadow Validator
        let mut missed = Vec::new();
        for bit in &tc.important_bits {
            // Check if important bit is in kept text OR in the legend
            if !kept_text.to_lowercase().contains(&bit.to_lowercase()) && !legend_str.to_lowercase().contains(&bit.to_lowercase()) {
                missed.push(*bit);
            }
        }

        let req_id = format!("lab_v15_{}", tc.name.replace(" ", "_"));
        let status = if missed.is_empty() { "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };

        let tx = conn.transaction()?;
        tx.execute("DELETE FROM audit_events WHERE request_id = ?", params![req_id])?;
        tx.execute("INSERT INTO audit_events (timestamp, request_id, command, exit_code, security_ms, shell_ms, proxy_ms, total_ms, input_bytes, output_bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![Utc::now().to_rfc3339(), req_id, tc.name, 0, 0, 0, 0, duration.as_millis() as i64, tc.input.len() as i64, kept_text.len() as i64])?;
        tx.execute("INSERT INTO audit_content (request_id, raw_input, final_output) VALUES (?, ?, ?)",
            params![req_id, tc.input, kept_text])?;
        for bit in &missed {
            tx.execute("INSERT INTO accuracy_failures (request_id, failed_line, missed_token, score_breakdown) VALUES (?, ?, ?, ?)",
                params![req_id, "v15_precision", bit, "Target Accuracy Violation"])?;
        }
        tx.commit()?;

        let comp_ratio = 100.0 - (kept_text.len() as f64 / tc.input.len() as f64 * 100.0);
        println!("{:<12} | {:<15} | Squeeze: {:>4.1}% | {}", tc.category, tc.name, comp_ratio, status);
        if !missed.is_empty() { println!("   ↳ ACCURACY FAILURE: {:?}", missed); }
    }

    Ok(())
}
