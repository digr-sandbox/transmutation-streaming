use std::collections::{HashMap, HashSet};
use regex::Regex;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use std::fs;
use std::path::PathBuf;
use sysinfo::System;
use rusqlite::{params, Connection};
use std::time::Instant;

/// --- THE PRUNING SUITE: v16 Global Lexicon & Delta Engine ---

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

/// TOON v2: Keys + Common Value Compaction
fn apply_toon_v2(text: &str, category: &str) -> (String, usize) {
    let mut result = text.to_string();
    if category == "JSON" {
        // 1. Key Unquoting
        let json_key_re = Regex::new(r#""(\w+)":\s*"#).unwrap();
        result = json_key_re.replace_all(&result, "$1: ").to_string();
        // 2. Value Compaction
        result = result.replace(": true", ": !t");
        result = result.replace(": false", ": !f");
        result = result.replace(": null", ": !n");
    }
    let ws_re = Regex::new(r"\s{2,}").unwrap();
    result = ws_re.replace_all(&result, " ").to_string();
    let saved = text.len().saturating_sub(result.len());
    (result, saved)
}

/// Feature: Numeric Delta Encoding (v16)
fn apply_delta_encoding(text: &str) -> (String, usize) {
    let original_len = text.len();
    let mut result = String::new();
    let mut last_num: Option<i64> = None;
    
    // Simple regex to find numbers in isolation
    let num_re = Regex::new(r"\b\d{4,}\b").unwrap(); 
    
    // This is a simplified demo of delta encoding for the lab
    let mut last_pos = 0;
    for mat in num_re.find_iter(text) {
        result.push_str(&text[last_pos..mat.start()]);
        let val: i64 = mat.as_str().parse().unwrap_or(0);
        if let Some(prev) = last_num {
            let delta = val - prev;
            if delta >= 0 {
                result.push_str(&format!("+{}", delta));
            } else {
                result.push_str(mat.as_str());
            }
        } else {
            result.push_str(mat.as_str());
        }
        last_num = Some(val);
        last_pos = mat.end();
    }
    result.push_str(&text[last_pos..]);
    
    let saved = original_len.saturating_sub(result.len());
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

fn generate_global_lexicon(words: &[String]) -> (HashMap<String, String>, String, usize) {
    let mut freq = HashMap::new();
    for w in words { if w.len() > 5 { *freq.entry(w.clone()).or_insert(0) += 1; } }
    
    let mut legend_map = HashMap::new();
    let mut legend_str = String::new();
    let mut savings = 0;
    let mut alias_idx = 'A'; // Use Uppercase for Global Lexicon

    let mut sorted_freq: Vec<_> = freq.into_iter().collect();
    sorted_freq.sort_by(|a, b| b.1.cmp(&a.1));

    for (word, count) in sorted_freq.into_iter().take(10) {
        if count > 1 {
            let alias = format!("@{}", alias_idx);
            let overhead = alias.len() + word.len() + 6;
            let potential = (word.len() - alias.len()) * count;
            if potential > overhead {
                legend_map.insert(word.clone(), alias.clone());
                legend_str.push_str(&format!("{}:\"{}\" ", alias, word));
                savings += potential - overhead;
                alias_idx = ((alias_idx as u8) + 1) as char;
            }
        }
    }
    (legend_map, legend_str.trim().to_string(), savings)
}

fn run_suite(words: &[String], config: &Config) -> Vec<WordAudit> {
    let mut freq_map = HashMap::new();
    for w in words { *freq_map.entry(w).or_insert(0) += 1; }
    let total = words.len() as f64;
    let mut audits = Vec::new();
    const WINDOW: usize = 10;

    for (idx, word) in words.iter().enumerate() {
        if is_protected(word) || word.starts_with('@') || word.starts_with('+') {
            audits.push(WordAudit { text: word.clone(), final_score: f64::INFINITY, kept: true });
            continue;
        }
        let count = freq_map.get(word).unwrap_or(&1);
        let idf = (total / *count as f64).ln();
        let stop_words: HashSet<&str> = ["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "it", "this", "that", "of", "be"].into_iter().collect();
        let pos = if stop_words.contains(word.to_lowercase().as_str()) { 0.05 } else { 0.80 };
        
        let start = idx.saturating_sub(WINDOW / 2);
        let end = (idx + WINDOW / 2).min(words.len());
        let window = &words[start..end];
        let unique = window.iter().collect::<HashSet<_>>().len();
        let entropy = unique as f64 / window.len() as f64;

        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight) + (entropy * config.entropy_weight);
        audits.push(WordAudit { text: word.clone(), final_score, kept: final_score >= config.base_threshold });
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
            name: "Rust Re-Build",
            input: "Compiling transmutation v0.4.0. Compiling transmutation v0.4.0. Compiling transmutation v0.4.0. Finished dev target(s) in 0.0s.".to_string(),
            important_bits: vec!["transmutation", "v0.4.0", "Finished"],
        },
        TestCase {
            category: "Server Logs",
            name: "Timestamp Delta",
            input: "1711821600: GET /api. 1711821605: GET /api. 1711821610: GET /api. 1711821660: GET /api.".to_string(),
            important_bits: vec!["GET", "/api"],
        },
        TestCase {
            category: "JSON",
            name: "Boolean Noise",
            input: r#"{"id": 1, "active": true, "verified": true, "flagged": false, "deleted": null}"#.to_string(),
            important_bits: vec!["active", "true", "deleted", "null"],
        },
    ]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let test_cases = get_test_cases();
    let config = Config { idf_weight: 0.25, pos_weight: 0.55, entropy_weight: 0.20, base_threshold: 1.0 };

    let db_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap();
    let db_path = db_dir.join("audit.db");
    let mut conn = Connection::open(&db_path)?;

    // 0. Setup Schema (v12+ Mandatory)
    conn.execute("PRAGMA foreign_keys = ON;", [])?;
    conn.execute(
        "CREATE TABLE IF NOT EXISTS audit_events (
            timestamp TEXT, request_id TEXT PRIMARY KEY, command TEXT, exit_code INTEGER,
            security_ms INTEGER, shell_ms INTEGER, proxy_ms INTEGER, total_ms INTEGER,
            input_bytes INTEGER, output_bytes INTEGER
        )", [],
    )?;
    conn.execute(
        "CREATE TABLE IF NOT EXISTS audit_content (
            request_id TEXT PRIMARY KEY, raw_input TEXT, final_output TEXT,
            FOREIGN KEY(request_id) REFERENCES audit_events(request_id) ON DELETE CASCADE
        )", [],
    )?;
    conn.execute(
        "CREATE TABLE IF NOT EXISTS accuracy_failures (
            id INTEGER PRIMARY KEY AUTOINCREMENT, request_id TEXT,
            failed_line TEXT, missed_token TEXT, score_breakdown TEXT,
            FOREIGN KEY(request_id) REFERENCES audit_events(request_id) ON DELETE CASCADE
        )", [],
    )?;

    println!("🧪 v16 GLOBAL LEXICON & DELTA SQUEEZE");
    println!("================================================================================\n");

    for tc in test_cases {
        let start_time = Instant::now();
        
        // 1. TOON v2
        let (toon_text, _) = apply_toon_v2(&tc.input, tc.category);
        
        // 2. Delta Encoding
        let (delta_text, _) = apply_delta_encoding(&toon_text);
        
        let raw_words: Vec<String> = delta_text.split_whitespace().map(|s| s.to_string()).collect();
        
        // 3. Global Lexicon
        let (legend_map, legend_str, _) = generate_global_lexicon(&raw_words);
        let mut processed_words = Vec::new();
        for w in raw_words { processed_words.push(legend_map.get(&w).cloned().unwrap_or(w)); }

        // 4. Pruning
        let result = run_suite(&processed_words, &config);
        let mut kept_text = String::new();
        if !legend_str.is_empty() { kept_text.push_str(&format!("LEGEND: {} | ", legend_str)); }
        for r in &result { if r.kept { kept_text.push_str(&r.text); kept_text.push(' '); } }
        
        let duration = start_time.elapsed();

        // Integrity Check
        let mut missed = Vec::new();
        for bit in &tc.important_bits {
            let b_lower = bit.to_lowercase();
            if !kept_text.to_lowercase().contains(&b_lower) && !legend_str.to_lowercase().contains(&b_lower) {
                missed.push(*bit);
            }
        }

        let req_id = format!("lab_v16_{}", tc.name.replace(" ", "_"));
        let status = if missed.is_empty() { "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };

        let tx = conn.transaction()?;
        tx.execute("DELETE FROM audit_events WHERE request_id = ?", params![req_id])?;
        tx.execute("INSERT INTO audit_events (timestamp, request_id, command, exit_code, security_ms, shell_ms, proxy_ms, total_ms, input_bytes, output_bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![Utc::now().to_rfc3339(), req_id, tc.name, 0, 0, 0, 0, duration.as_millis() as i64, tc.input.len() as i64, kept_text.len() as i64])?;
        tx.execute("INSERT INTO audit_content (request_id, raw_input, final_output) VALUES (?, ?, ?)",
            params![req_id, tc.input, kept_text])?;
        tx.commit()?;

        let comp_ratio = 100.0 - (kept_text.len() as f64 / tc.input.len() as f64 * 100.0);
        println!("{:<12} | {:<15} | Squeeze: {:>4.1}% | {}", tc.category, tc.name, comp_ratio, status);
        if !missed.is_empty() { println!("   ↳ ACCURACY FAILURE: {:?}", missed); }
    }

    Ok(())
}
