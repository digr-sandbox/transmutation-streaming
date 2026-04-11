//! Agentic Engine for Architectural Reconnaissance and Structural Extraction
//! 
//! Provides Latent-K based structural skeletonization and Architecture Code Maps.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use regex::Regex;
use rusqlite::Connection;
use walkdir::WalkDir;
use std::io::{BufRead, BufReader, Read};
use std::fs::File;

fn flatten_toon(val: &serde_json::Value, out: &mut Vec<String>, prefix: &str) {
    match val {
        serde_json::Value::Object(map) => {
            for (k, v) in map {
                let new_prefix = if prefix.is_empty() { k.clone() } else { format!("{prefix}.{k}") };
                flatten_toon(v, out, &new_prefix);
            }
        }
        serde_json::Value::Array(arr) => {
            for (i, v) in arr.iter().enumerate() {
                let new_prefix = format!("{prefix}[{i}]");
                flatten_toon(v, out, &new_prefix);
            }
        }
        serde_json::Value::String(s) => {
            out.push(format!("{prefix}: {s}"));
        }
        _ => {
            out.push(format!("{prefix}: {}", val));
        }
    }
}

pub fn stream_toon(
    file_path: &str,
    search_pattern: Option<&str>,
    offset: usize,
    limit: usize,
) -> Result<String, std::io::Error> {
    let mut raw_content = std::fs::read_to_string(file_path)?;
    
    // Remove BOM if present
    if raw_content.starts_with('\u{feff}') {
        raw_content = raw_content[3..].to_string();
    }

    let mut all_toon_lines = Vec::new();

    // Strategy: Parse using serde_json::from_str for whole DOM flattening.
    // If it fails (too deep), we fallback to line-by-line.
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(&raw_content) {
        flatten_toon(&value, &mut all_toon_lines, "root");
    } else {
        // Fallback: NDJSON
        for line in raw_content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() { continue; }
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(trimmed) {
                flatten_toon(&val, &mut all_toon_lines, "node");
            } else {
                all_toon_lines.push(trimmed.to_string());
            }
        }
    }

    let re = search_pattern.and_then(|p| Regex::new(p).ok());
    let mut match_count = 0;
    let mut lines_added = 0;
    let mut has_more = false;
    let mut candidates = Vec::new();

    for t_line in all_toon_lines {
        let matches = match &re {
            Some(regex) => regex.is_match(&t_line),
            None => true,
        };

        if matches {
            if match_count >= offset {
                if lines_added < limit {
                    candidates.push(t_line);
                    lines_added += 1;
                } else {
                    has_more = true;
                    break;
                }
            }
            match_count += 1;
        }
    }

    // --- OPTIMIZATION: Adaptive Breadcrumb Context (R-TOON) ---
    let mut breadcrumb = String::new();
    let mut final_lines = candidates;

    if !final_lines.is_empty() {
        if let Some(first) = final_lines.first().cloned() {
            let parts: Vec<&str> = first.split(':').collect();
            if parts.len() > 1 {
                let path_parts: Vec<&str> = parts[0].split('.').collect();
                let mut common_path = Vec::new();
                for i in 0..path_parts.len() {
                    let current_test = path_parts[..=i].join(".");
                    if final_lines.iter().all(|l| l.starts_with(&current_test)) {
                        common_path.push(path_parts[i]);
                    } else { break; }
                }
                if !common_path.is_empty() {
                    breadcrumb = common_path.join(".");
                    let strip_len = breadcrumb.len();
                    for line in &mut final_lines {
                        if line.starts_with(&breadcrumb) {
                            *line = format!(".{}", &line[strip_len..]);
                        }
                    }
                    if breadcrumb.len() > 200 {
                        breadcrumb = format!("{}...{}", &breadcrumb[..50], &breadcrumb[breadcrumb.len()-50..]);
                    }
                }
            }
        }
    }

    let header = format!("# ⚡ TOON STREAM [Matches: {} | Offset: {} | Limit: {} | Has More: {}]\n", 
        lines_added, offset, limit, if has_more { "TRUE" } else { "FALSE" });
    let mut out = header;
    if !breadcrumb.is_empty() { out.push_str(&format!("# CONTEXT: {}\n", breadcrumb)); }
    out.push_str("---\n");
    if final_lines.is_empty() { out.push_str("(No matches found or EOF reached)\n"); }
    else { for l in final_lines { out.push_str(&l); out.push('\n'); } }
    if has_more { out.push_str("\n--- [TRUNCATED: Use higher offset to see more results] ---\n"); }
    Ok(out)
}

/// Engine for architectural mapping and structural code extraction.
pub struct CodeMapEngine {
    /// SQLite connection for edge and symbol storage.
    pub conn: std::sync::Mutex<Connection>,
}

impl std::fmt::Debug for CodeMapEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CodeMapEngine").finish()
    }
}

impl CodeMapEngine {
    /// Create a new CodeMapEngine with an in-memory SQLite database.
    pub fn new() -> Self {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute(
            "CREATE TABLE edges (source TEXT, target TEXT, UNIQUE(source, target))",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE symbols (file TEXT, name TEXT, UNIQUE(file, name))",
            [],
        )
        .unwrap();
        Self {
            conn: std::sync::Mutex::new(conn),
        }
    }

    /// Extract edges (imports) and symbols (definitions) from source content.
    pub fn extract_data(content: &str, file_path: &str) -> (HashSet<String>, HashSet<String>) {
        let mut edges = HashSet::new();
        let mut symbols = HashSet::new();

        let rust_import_re = Regex::new(r"use\s+crate::([a-zA-Z0-9_:]+)").unwrap();
        let rust_mod_re = Regex::new(r"pub\s+mod\s+([a-zA-Z0-9_]+)").unwrap();
        let rust_symbol_re =
            Regex::new(r"pub\s+(struct|enum|trait|type|fn)\s+([a-zA-Z0-9_]+)").unwrap();

        for cap in rust_import_re.captures_iter(content) {
            let mut path = "src".to_string();
            for part in cap[1].split("::") {
                if part == "*" || part.starts_with('{') {
                    break;
                }
                path.push('/');
                path.push_str(part);
            }
            edges.insert(format!("{path}.rs"));
            edges.insert(format!("{path}/mod.rs"));
        }

        for cap in rust_mod_re.captures_iter(content) {
            let parent = Path::new(file_path)
                .parent()
                .unwrap()
                .to_string_lossy()
                .replace('\\', "/");
            edges.insert(format!("{parent}/{}.rs", &cap[1]));
            edges.insert(format!("{parent}/{}/mod.rs", &cap[1]));
        }

        for cap in rust_symbol_re.captures_iter(content) {
            symbols.insert(cap[2].to_string());
        }

        (
            edges
                .into_iter()
                .filter(|p| Path::new(p).exists())
                .collect(),
            symbols,
        )
    }

    /// Build the initial architectural map by scanning the src directory.
    pub fn build_initial_map(&self) {
        let mut all_data = Vec::new();
        for entry in WalkDir::new("src").into_iter().filter_map(|e| e.ok()) {
            if entry.path().extension().is_some_and(|ext| ext == "rs") {
                let source = entry.path().to_string_lossy().replace('\\', "/");
                if let Ok(content) = std::fs::read_to_string(entry.path()) {
                    let (edges, symbols) = Self::extract_data(&content, &source);
                    all_data.push((source, edges, symbols));
                }
            }
        }

        let conn = self.conn.lock().unwrap();
        for (source, edges, symbols) in all_data {
            for target in edges {
                let _ = conn.execute(
                    "INSERT OR IGNORE INTO edges (source, target) VALUES (?1, ?2)",
                    rusqlite::params![source, target],
                );
            }
            for sym in symbols {
                let _ = conn.execute(
                    "INSERT OR IGNORE INTO symbols (file, name) VALUES (?1, ?2)",
                    rusqlite::params![source, sym],
                );
            }
        }
    }

    /// Read the architectural code map for a specific file.
    pub fn read_code_map(&self, filename: &str) -> String {
        let mut imports_from = Vec::new();
        let mut imported_by = Vec::new();
        let conn = self.conn.lock().unwrap();

        if let Ok(mut stmt) = conn.prepare("SELECT target FROM edges WHERE source = ?1") {
            if let Ok(rows) = stmt.query_map([filename], |row| row.get::<_, String>(0)) {
                for r in rows.flatten() {
                    imports_from.push(r);
                }
            }
        }

        if let Ok(mut stmt2) = conn.prepare("SELECT source FROM edges WHERE target = ?1") {
            if let Ok(rows) = stmt2.query_map([filename], |row| row.get::<_, String>(0)) {
                for r in rows.flatten() {
                    imported_by.push(r);
                }
            }
        }

        let mut out = format!("[ARCHITECTURE CODE MAP]\nFile: {filename}\n");
        out.push_str("Imports From: ");
        if imports_from.is_empty() {
            out.push_str("(None)\n");
        } else {
            out.push_str(&imports_from.join(", "));
            out.push('\n');
        }
        out.push_str("Imported By: ");
        if imported_by.is_empty() {
            out.push_str("(None)\n");
        } else {
            out.push_str(&imported_by.join(", "));
            out.push('\n');
        }
        out
    }

    /// Perform global architectural reconnaissance.
    pub fn query_recon(&self) -> String {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT DISTINCT source FROM edges").unwrap();
        let rows = stmt.query_map([], |row| row.get::<_, String>(0)).unwrap();

        let mut clusters: HashMap<String, Vec<String>> = HashMap::new();
        for path in rows.flatten() {
            let parts: Vec<&str> = path.split('/').collect();
            if parts.len() > 1 {
                clusters
                    .entry(parts[..parts.len() - 1].join("/"))
                    .or_default()
                    .push(parts.last().unwrap().to_string());
            }
        }

        let mut out = "[ARCHITECTURAL RECONNAISSANCE]\n".to_string();
        for (dir, files) in clusters {
            out.push_str(&format!("- {dir}: [{count} files]\n", count = files.len()));
        }
        out
    }

    /// Calculate the blast radius of a symbol change.
    pub fn query_impact(&self, symbol: &str) -> String {
        let conn = self.conn.lock().unwrap();

        let mut stmt_def = conn
            .prepare("SELECT file FROM symbols WHERE name = ?1")
            .unwrap();
        let def_files: Vec<String> = stmt_def
            .query_map([symbol], |row| row.get(0))
            .unwrap()
            .flatten()
            .collect();

        let mut affected = HashSet::new();

        for f in &def_files {
            let mut stmt_imp = conn
                .prepare("SELECT source FROM edges WHERE target = ?1")
                .unwrap();
            let rows = stmt_imp
                .query_map([f], |row| row.get::<_, String>(0))
                .unwrap();
            for r in rows.flatten() {
                affected.insert(r);
            }
        }

        for entry in WalkDir::new("src").into_iter().filter_map(|e| e.ok()) {
            if entry.path().extension().is_some_and(|ext| ext == "rs") {
                let path = entry.path().to_string_lossy().replace('\\', "/");
                if def_files.contains(&path) {
                    continue;
                }
                if let Ok(content) = std::fs::read_to_string(entry.path()) {
                    if content.contains(symbol) {
                        affected.insert(path);
                    }
                }
            }
        }

        let def_info = if def_files.is_empty() {
            "(Unknown)".to_string()
        } else {
            def_files.join(", ")
        };
        let mut out = format!("[BLAST RADIUS: {symbol}]\nDefined in: {def_info}\nFiles affected:\n");

        if affected.is_empty() {
            out.push_str("  (No usage found)\n");
        } else {
            for path in affected {
                out.push_str(&format!("  - {path}\n"));
            }
        }
        out
    }
}

pub fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_import = false;
    let mut depth = 0;
    let mut in_structural = false;

    let boredom_table: HashSet<&str> = [
        "if", "else", "let", "var", "const", "return", "public", "private", "protected",
        "class", "function", "fn", "void", "int", "char", "string", "bool", "true", "false",
        "import", "from", "use", "include", "struct", "impl", "type", "interface", "package",
        "namespace", "static", "async", "await", "try", "catch", "throw", "new",
        "this", "self", "super", "for", "while", "do", "switch", "case", "default", "break",
        "continue", "in", "of", "as", "is",
    ]
    .iter()
    .cloned()
    .collect();

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if (trimmed.starts_with("//")
            || trimmed.starts_with('#')
            || trimmed.starts_with("/*")
            || trimmed.starts_with('*')
            || trimmed.starts_with('%')
            || trimmed.starts_with("--"))
            && !trimmed.contains('@')
            && !trimmed.contains("#[")
        {
            continue;
        }
        if trimmed.contains("JUNK_")
            || trimmed.contains("LICENSE_HEADER")
            || trimmed.contains("boilerplate")
        {
            continue;
        }

        if trimmed.starts_with("import ")
            || trimmed.starts_with("use ")
            || trimmed.starts_with("#include")
            || trimmed.starts_with("package ")
            || trimmed.starts_with("-module")
            || trimmed.starts_with("require")
        {
            if trimmed.contains('{') && !trimmed.contains('}') {
                in_import = true;
            }
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') || trimmed.ends_with('.') {
                in_import = false;
            }
            continue;
        }
        if in_import {
            lines.push(line.to_string());
            if trimmed.contains('}') || trimmed.contains(';') || trimmed.ends_with('.') {
                in_import = false;
            }
            continue;
        }

        let open_braces = trimmed.chars().filter(|&c| c == '{').count();
        let close_braces = trimmed.chars().filter(|&c| c == '}').count();
        let was_at_root = depth == 0;

        let is_structural = trimmed.contains("struct")
            || trimmed.contains("typedef")
            || trimmed.contains("interface")
            || trimmed.contains("enum")
            || trimmed.to_uppercase().contains("TABLE")
            || trimmed.starts_with("type ")
            || trimmed.starts_with("query ")
            || trimmed.starts_with("mutation ")
            || trimmed.starts_with("BEGIN");

        if is_structural {
            in_structural = true;
        }

        let mut score = 0;

        if trimmed.starts_with('@')
            || trimmed.starts_with("#[")
            || trimmed.starts_with("#!")
            || trimmed.starts_with("<?php")
            || trimmed.starts_with("-module")
        {
            score += 30;
        }

        if trimmed.ends_with('{')
            || trimmed.ends_with(':')
            || trimmed.ends_with('[')
            || is_structural
            || (trimmed.contains("func ") && !trimmed.contains('}'))
            || trimmed.contains("::")
            || trimmed.contains("->")
        {
            score += 20;
        }

        if trimmed.starts_with('+')
            || trimmed.starts_with('-')
            || trimmed.starts_with('>')
            || trimmed.to_uppercase().contains("INSERT ")
            || trimmed.to_uppercase().contains("SELECT ")
            || trimmed.to_uppercase().contains("UPDATE ")
            || trimmed.to_uppercase().contains("PRIMARY KEY")
            || trimmed.to_uppercase().contains("BEGIN")
            || trimmed.to_uppercase().contains("COMMIT")
        {
            score += 20;
        }

        if trimmed.contains("await")
            || trimmed.contains("return")
            || trimmed.contains("throw")
            || trimmed.contains("yield")
            || trimmed.contains("yield*")
            || trimmed.contains("malloc")
            || trimmed.contains("free")
            || trimmed.contains("strdup")
            || trimmed.contains("new ")
        {
            score += 15;
        }

        if trimmed.contains("->")
            || trimmed.contains('*')
            || trimmed.contains('&')
            || (trimmed.contains('.') && (trimmed.contains('(') || trimmed.contains('[')))
            || (trimmed.contains(':') && !trimmed.contains('{'))
        {
            score += 10;
        }

        let has_high_signal = trimmed
            .split(|c: char| !c.is_alphanumeric() && c != '@' && c != '_')
            .any(|token| {
                if token.is_empty() || boredom_table.contains(token.to_lowercase().as_str()) {
                    return false;
                }
                let has_upper = token.chars().any(|c| c.is_uppercase());
                let has_lower = token.chars().any(|c| c.is_lowercase());
                token.len() > 2
                    && (has_upper && has_lower
                        || token.contains('_')
                        || token.ends_with('*')
                        || token.chars().all(|c| c.is_uppercase()))
            });

        if has_high_signal {
            score += 5;
        }

        let threshold = if was_at_root || in_structural { 1 } else { 10 };

        if score >= threshold {
            let is_complex_line =
                trimmed.contains('(') || (trimmed.contains(':') && !trimmed.contains('{'));
            if was_at_root && trimmed.ends_with('{') && !is_complex_line && !is_structural {
                lines.push(format!("{} ... }}", line.trim_end_matches('{').trim_end()));
            } else {
                lines.push(line.to_string());
            }
        }

        depth = depth + open_braces as i32 - close_braces as i32;
        if depth <= 0 {
            depth = 0;
            in_structural = false;
        }
    }
    lines.join("\n")
}
