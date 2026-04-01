use std::collections::{HashMap, HashSet};
use regex::Regex;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use std::fs;
use std::path::PathBuf;
use sysinfo::System;
use rusqlite::{params, Connection};
use std::time::Instant;

/// --- THE PRUNING SUITE: v21 Semantic Token Compaction ---

#[derive(Clone)]
struct Config {
    idf_weight: f64,
    pos_weight: f64,
    entropy_weight: f64,
    target_compression: f64,
}

#[derive(Clone, Debug)]
struct Token {
    text: String,
    is_immune: bool,
    final_score: f64,
    kept: bool,
}

/// Feature: Semantic Token Squeezer (v21)
fn semantic_squeeze(text: &str) -> String {
    let mut result = text.to_string();
    
    // 1. Timestamp Stripping: [30/Mar/2026:18:00:01] -> 18:00:01
    let time_re = Regex::new(r"\[\d{2}/\w{3}/\d{4}:(\d{2}:\d{2}:\d{2})\]").unwrap();
    result = time_re.replace_all(&result, "$1").to_string();
    
    // 2. IPv4 Aliasing (First 3 instances)
    let ip_re = Regex::new(r"\b\d{1,3}\.\d+\.\d+\.\d+\b").unwrap();
    let mut ips = HashMap::new();
    let mut alias_idx = 1;
    
    // Pass 1: Find IPs
    for mat in ip_re.find_iter(&result.clone()) {
        ips.entry(mat.as_str().to_string()).or_insert_with(|| {
            let a = format!("@{}", alias_idx);
            alias_idx += 1;
            a
        });
    }
    
    // Pass 2: Replace
    for (ip, alias) in ips {
        result = result.replace(&ip, &alias);
    }
    
    result
}

fn is_protected(word: &str) -> bool {
    lazy_static::lazy_static! {
        static ref IP_RE: Regex = Regex::new(r"^(@\d+|\d{1,3}\.\d+\.\d+\.\d+)$").unwrap();
        static ref PATH_RE: Regex = Regex::new(r"(?i)^[/\\]?[\w/\\.-]+\.[a-z0-9]{1,5}$").unwrap();
        static ref SEMANTIC_RE: Regex = Regex::new(r"(?i)^(error|fail|panic|warn|critical|debug|success|successfully|done|finished|status|login|node|pod|ok|get|post|200|403|500)$").unwrap();
    }
    let clean = word.trim_matches(|c: char| !c.is_alphanumeric() && c != '.' && c != '/' && c != '@');
    IP_RE.is_match(clean) || PATH_RE.is_match(clean) || SEMANTIC_RE.is_match(clean)
}

fn run_squeeze(words: &[String], config: &Config) -> Vec<Token> {
    let mut freq_map = HashMap::new();
    for w in words { *freq_map.entry(w).or_insert(0) += 1; }
    let total = words.len() as f64;

    let mut tokens = Vec::new();
    for (idx, word) in words.iter().enumerate() {
        if is_protected(word) {
            tokens.push(Token { text: word.clone(), is_immune: true, final_score: f64::INFINITY, kept: true });
            continue;
        }
        let count = freq_map.get(word).unwrap_or(&1);
        let idf = (total / *count as f64).ln();
        let boring: HashSet<&str> = ["the", "a", "an", "and", "or", "is", "was", "in", "on", "at", "to", "for", "it", "this", "that", "of", "be", "info", "using"].into_iter().collect();
        let pos = if boring.contains(word.to_lowercase().as_str()) { 0.05 } else { 0.85 };
        let final_score = (idf * config.idf_weight) + (pos * config.pos_weight);
        tokens.push(Token { text: word.clone(), is_immune: false, final_score, kept: false });
    }

    let mut non_immune_indices: Vec<usize> = tokens.iter().enumerate().filter(|(_, t)| !t.is_immune).map(|(i, _)| i).collect();
    non_immune_indices.sort_by(|&a, &b| tokens[b].final_score.partial_cmp(&tokens[a].final_score).unwrap());
    let keep_count = (non_immune_indices.len() as f64 * (1.0 - config.target_compression)) as usize;
    for &idx in non_immune_indices.iter().take(keep_count) { tokens[idx].kept = true; }
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
        TestCase {
            category: "Server Logs",
            name: "Apache Squeeze",
            input: "192.168.1.10 - - [30/Mar/2026:18:00:01] \"GET /api/v1/users HTTP/1.1\" 200 1243. 192.168.1.10 - - [30/Mar/2026:18:00:02] \"POST /login HTTP/1.1\" 403 512.".to_string(),
            important_bits: vec!["192.168.1.10", "200", "GET", "403", "18:00:01"],
        },
    ]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let test_cases = get_test_cases();
    let config = Config { idf_weight: 0.3, pos_weight: 0.7, entropy_weight: 0.0, target_compression: 0.6 };

    println!("🧪 v21 SEMANTIC SQUEEZE (Ralph Loop 6)");
    println!("Goal: Break 50% Compaction | Accuracy Goal: 100%");
    println!("================================================================================\n");

    for tc in test_cases {
        let squeezed_input = semantic_squeeze(&tc.input);
        let words: Vec<String> = squeezed_input.split_whitespace().map(|s| s.to_string()).collect();
        let tokens = run_squeeze(&words, &config);

        let mut kept_text = String::new();
        for t in &tokens { if t.kept { kept_text.push_str(&t.text); kept_text.push(' '); } }

        let mut missed = Vec::new();
        for bit in &tc.important_bits {
            if !kept_text.to_lowercase().contains(&bit.to_lowercase()) { missed.push(*bit); }
        }

        let status = if missed.is_empty() { "\x1b[32mPASS\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
        let comp_ratio = 100.0 - (kept_text.len() as f64 / tc.input.len() as f64 * 100.0);
        println!("{:<12} | {:<15} | Squeeze: {:>4.1}% | {}", tc.category, tc.name, comp_ratio, status);
        if !missed.is_empty() { println!("   ↳ FAILURE: {:?}", missed); }
        println!("   ↳ Result: \"{}\"", kept_text.trim());
    }
    Ok(())
}
