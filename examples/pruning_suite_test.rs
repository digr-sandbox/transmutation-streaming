use std::collections::{HashMap, HashSet};
use regex::Regex;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use std::fs;
use std::path::PathBuf;
use sysinfo::System;
use rusqlite::{params, Connection};
use std::time::Instant;

/// --- THE PRUNING SUITE: v14 Aggressive Squeeze Engine ---

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

fn is_protected(word: &str) -> bool {
    lazy_static::lazy_static! {
        static ref IP_RE: Regex = Regex::new(r"^\d{1,3}\.\d+\.\d+\.\d+$").unwrap();
        static ref PATH_RE: Regex = Regex::new(r"(?i)^[/\\]?[\w/\\.-]+\.[a-z0-9]{1,5}$").unwrap();
        static ref TAG_RE: Regex = Regex::new(r"^<[^>]+>$").unwrap();
        static ref HEX_RE: Regex = Regex::new(r"^0x[0-9a-fA-F]+$").unwrap();
        static ref SEMANTIC_RE: Regex = Regex::new(r"(?i)^(error|fail|panic|exception|fatal|warn|critical|debug|unresolved|timeout|refused|denied|abort|oomkilled|kubelet|pod|node|impl|async|fn|result|select|insert|update|join|where|group|by|order|limit|begin|commit|git|diff|modified|untracked)$").unwrap();
    }
    let clean = word.trim_matches(|c: char| !c.is_alphanumeric() && c != '.' && c != '/');
    IP_RE.is_match(clean) || PATH_RE.is_match(clean) || TAG_RE.is_match(word) || HEX_RE.is_match(clean) || SEMANTIC_RE.is_match(clean)
}

fn run_suite(words: &[String], config: &Config, category: &str) -> Vec<WordAudit> {
    let mut freq_map = HashMap::new();
    for w in words { *freq_map.entry(w).or_insert(0) += 1; }
    let total = words.len() as f64;

    let threshold = match category {
        "Code" | "JSON" | "LLM Prompt" | "SQL Logs" => config.base_threshold * 0.5,
        _ => config.base_threshold,
    };

    let mut audits = Vec::new();
    const WINDOW: usize = 10;

    for (idx, word) in words.iter().enumerate() {
        if is_protected(word) {
            audits.push(WordAudit { text: word.clone(), final_score: f64::INFINITY, kept: true });
            continue;
        }

        let count = freq_map.get(word).unwrap_or(&1);
        let idf = (total / *count as f64).ln();
        
        // v14 Aggressive Verb/Status list
        let boring_words: HashSet<&str> = ["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "with", "by", "from", "as", "it", "this", "that", "of", "be", "info", "using", "successfully", "checking", "found", "done", "finished", "started", "output", "saved"].into_iter().collect();
        let pos = if boring_words.contains(word.to_lowercase().as_str()) { 0.05 } else { 0.85 };

        let start = idx.saturating_sub(WINDOW / 2);
        let end = (idx + WINDOW / 2).min(words.len());
        let window = &words[start..end];
        let unique = window.iter().collect::<HashSet<_>>().len();
        let entropy = unique as f64 / window.len() as f64;

        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight) + (entropy * config.entropy_weight);
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
            input: "info: request processed. info: request processed. info: request processed. error: connection reset.".to_string(),
            important_bits: vec!["processed", "reset"],
        },
        TestCase {
            category: "SQL Logs",
            name: "Slow Join",
            input: "SLOW QUERY: SELECT email FROM users JOIN orders ON users.id = orders.user_id WHERE total > 5000;".to_string(),
            important_bits: vec!["JOIN", "5000"],
        },
    ]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let test_cases = get_test_cases();
    let config = Config { idf_weight: 0.25, pos_weight: 0.55, entropy_weight: 0.20, base_threshold: 1.5 }; // RAISED THRESHOLD

    let db_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap();
    let db_path = db_dir.join("audit.db");
    let mut conn = Connection::open(&db_path)?;

    println!("🧪 v14 AGGRESSIVE SQUEEZE: COMPACTION EVALUATION");
    println!("================================================================================\n");

    for tc in test_cases {
        let start_time = Instant::now();
        let words: Vec<String> = tc.input.split_whitespace().map(|s| s.to_string()).collect();
        
        // Deduplication (v14)
        let mut seen_lines = HashSet::new();
        let mut deduped_words = Vec::new();
        for w in words {
            if !seen_lines.contains(&w) {
                deduped_words.push(w.clone());
                // Simple word-level dedup for this lab
                if w.len() > 10 { seen_lines.insert(w); }
            }
        }

        let result = run_suite(&deduped_words, &config, tc.category);
        let mut kept_text = String::new();
        for r in &result { if r.kept { kept_text.push_str(&r.text); kept_text.push(' '); } }
        let duration = start_time.elapsed();

        let mut missed = Vec::new();
        for bit in &tc.important_bits {
            if !kept_text.to_lowercase().contains(&bit.to_lowercase()) { missed.push(*bit); }
        }

        let req_id = format!("lab_v14_{}", tc.name.replace(" ", "_"));
        let status = if missed.is_empty() { "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };

        let tx = conn.transaction()?;
        tx.execute("DELETE FROM audit_events WHERE request_id = ?", params![req_id])?;
        tx.execute("INSERT INTO audit_events (timestamp, request_id, command, exit_code, security_ms, shell_ms, proxy_ms, total_ms, input_bytes, output_bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![Utc::now().to_rfc3339(), req_id, tc.name, 0, 0, 0, 0, duration.as_millis() as i64, tc.input.len() as i64, kept_text.len() as i64])?;
        tx.execute("INSERT INTO audit_content (request_id, raw_input, final_output) VALUES (?, ?, ?)",
            params![req_id, tc.input, kept_text])?;
        for bit in &missed {
            tx.execute("INSERT INTO accuracy_failures (request_id, failed_line, missed_token, score_breakdown) VALUES (?, ?, ?, ?)",
                params![req_id, "v14_squeeze", bit, "High Aggression Pruning"])?;
        }
        tx.commit()?;

        let comp_ratio = 100.0 - (kept_text.len() as f64 / tc.input.len() as f64 * 100.0);
        println!("{:<12} | {:<15} | Compaction: {:>4.1}% | {}", tc.category, tc.name, comp_ratio, status);
        if !missed.is_empty() { println!("   ↳ Lost bits recorded: {:?}", missed); }
    }

    Ok(())
}
