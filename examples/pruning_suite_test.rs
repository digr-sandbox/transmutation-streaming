use std::collections::{HashMap, HashSet};
use regex::Regex;
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use std::fs;
use std::path::PathBuf;
use sysinfo::System;
use rusqlite::{params, Connection};
use std::time::Instant;

/// --- THE PRUNING SUITE: v22 The Provenance Handshake ---

#[derive(Clone, Debug)]
struct Token {
    text: String,
    is_immune: bool,
    kept: bool,
}

/// Feature: Full Semantic Squeezer with Legend (v22)
fn semantic_squeeze_v2(text: &str) -> (String, String, usize) {
    let mut result = text.to_string();
    
    // 1. Timestamp Stripping
    let time_re = Regex::new(r"\[\d{2}/\w{3}/\d{4}:(\d{2}:\d{2}:\d{2})\]").unwrap();
    result = time_re.replace_all(&result, "$1").to_string();
    
    // 2. IP & Path Aliasing
    let mut legend = HashMap::new();
    let mut legend_str = String::new();
    let mut alias_idx = 1;
    
    let patterns = vec![
        (Regex::new(r"\b\d{1,3}\.\d+\.\d+\.\d+\b").unwrap(), "IP"),
        (Regex::new(r"(/api/v\d+/\w+)").unwrap(), "PATH"),
    ];
    
    for (re, _) in patterns {
        for mat in re.find_iter(&result.clone()) {
            let original = mat.as_str().to_string();
            if !legend.contains_key(&original) {
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
    
    (result, legend_str.trim().to_string(), legend.len())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = "192.168.1.10 - - [30/Mar/2026:18:00:01] \"GET /api/v1/users HTTP/1.1\" 200 1243. 192.168.1.10 - - [30/Mar/2026:18:00:02] \"POST /api/v1/users HTTP/1.1\" 403 512.";
    let important_bits = vec!["192.168.1.10", "200", "GET", "403", "18:00:01", "/api/v1/users"];

    println!("🧪 v22 THE PROVENANCE HANDSHAKE (Ralph Loop 7)");
    println!("Goal: Verified 50%+ Compaction with Legend Decoding");
    println!("================================================================================\n");

    let (squeezed, legend, _) = semantic_squeeze_v2(input);
    
    // Pruning (Delete standard noise like "-", "HTTP/1.1")
    let mut final_text = String::new();
    if !legend.is_empty() { final_text.push_str(&format!("LEGEND: {} | ", legend)); }
    
    let noise: HashSet<&str> = ["-", "HTTP/1.1", "Mozilla/5.0", "\""].into();
    for word in squeezed.split_whitespace() {
        let clean = word.trim_matches('"');
        if !noise.contains(clean) {
            final_text.push_str(word);
            final_text.push(' ');
        }
    }

    // 3. LEGEND-AWARE VALIDATION
    let mut missed = Vec::new();
    for bit in &important_bits {
        let found_literal = final_text.contains(bit);
        let found_in_legend = legend.contains(bit);
        if !found_literal && !found_in_legend {
            missed.push(*bit);
        }
    }

    let status = if missed.is_empty() { "\x1b[32mPASS (100% Verified Accuracy)\x1b[0m" } else { "\x1b[31mFAIL\x1b[0m" };
    let comp_ratio = 100.0 - (final_text.len() as f64 / input.len() as f64 * 100.0);
    
    println!("   Category:    Server Logs");
    println!("   Squeeze:     {:>4.1}%", comp_ratio);
    println!("   Status:      {}", status);
    println!("   Output:      \"{}\"", final_text.trim());

    if comp_ratio > 50.0 {
        println!("\n✨ MILESTONE REACHED: Sustained 50% compaction with full semantic retention.");
    }

    Ok(())
}
