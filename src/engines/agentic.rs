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
use serde::Deserialize;

fn flatten_toon_optimized(val: &serde_json::Value, out: &mut Vec<String>, prefix: &str, is_element_root: bool) {
    match val {
        serde_json::Value::Object(map) => {
            if is_element_root {
                out.push(format!("[{prefix}]"));
            }
            for (k, v) in map {
                let new_prefix = if is_element_root { format!(".{k}") } else { format!("{prefix}.{k}") };
                flatten_toon_optimized(v, out, &new_prefix, false);
            }
        }
        serde_json::Value::Array(arr) => {
            let all_primitives = arr.iter().all(|v| v.is_string() || v.is_number() || v.is_boolean());
            if all_primitives && !arr.is_empty() {
                let vals: Vec<String> = arr.iter().map(|v| v.to_string().trim_matches('"').to_string()).collect();
                out.push(format!("{prefix}: {}", vals.join(" ")));
            } else {
                if is_element_root {
                    out.push(format!("[{prefix}]"));
                }
                for (i, v) in arr.iter().enumerate() {
                    let new_prefix = if is_element_root { format!("[{i}]") } else { format!("{prefix}[{i}]") };
                    flatten_toon_optimized(v, out, &new_prefix, v.is_object());
                }
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

#[derive(Debug)]
enum Context {
    Object { expecting_key: bool },
    Array { index: usize },
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum PathSeg {
    Key(String),
    Index(usize),
}

fn format_path(path: &[PathSeg]) -> String {
    let mut s = String::from("root");
    for p in path {
        match p {
            PathSeg::Key(k) => { s.push('.'); s.push_str(k); },
            PathSeg::Index(i) => { s.push('['); s.push_str(&i.to_string()); s.push(']'); },
        }
    }
    s
}

fn skip_whitespace(iter: &mut std::iter::Peekable<impl Iterator<Item=std::io::Result<u8>>>) {
    while let Some(res) = iter.peek() {
        if let Ok(b) = res {
            if b.is_ascii_whitespace() {
                iter.next();
            } else {
                break;
            }
        } else {
            break;
        }
    }
}

fn read_string(iter: &mut std::iter::Peekable<impl Iterator<Item=std::io::Result<u8>>>, truncate_len: usize) -> String {
    let mut s = String::new();
    iter.next(); // skip quote
    let mut escaped = false;
    let mut len = 0;
    let mut truncated = false;
    while let Some(Ok(b)) = iter.next() {
        if escaped {
            if !truncated {
                match b {
                    b'n' => s.push('\n'),
                    b'r' => s.push('\r'),
                    b't' => s.push('\t'),
                    b'"' => s.push('"'),
                    b'\\' => s.push('\\'),
                    b'/' => s.push('/'),
                    b'b' => s.push('\x08'),
                    b'f' => s.push('\x0C'),
                    _ => s.push(b as char),
                }
                len += 1;
            }
            escaped = false;
        } else if b == b'\\' {
            escaped = true;
        } else if b == b'"' {
            break;
        } else {
            if len < truncate_len {
                s.push(b as char);
                len += 1;
            } else if !truncated {
                s.push_str("... [TRUNCATED]");
                truncated = true;
            }
        }
    }
    s
}

fn read_primitive(iter: &mut std::iter::Peekable<impl Iterator<Item=std::io::Result<u8>>>) -> String {
    let mut s = String::new();
    let mut len = 0;
    let mut truncated = false;
    while let Some(Ok(b)) = iter.peek() {
        let b = *b;
        if b == b',' || b == b']' || b == b'}' || b.is_ascii_whitespace() {
            break;
        }
        if len < 1000 {
            s.push(b as char);
            len += 1;
        } else if !truncated {
            s.push_str("... [TRUNCATED]");
            truncated = true;
        }
        iter.next();
    }
    s
}

pub fn stream_toon(
    file_path: &str,
    search_pattern: Option<&str>,
    offset: usize,
    limit: usize,
) -> Result<String, std::io::Error> {
    use std::io::Read;
    
    let file = std::fs::File::open(file_path)?;
    let reader = std::io::BufReader::new(file);
    let mut iter = reader.bytes().peekable();
    let re = search_pattern.and_then(|p| Regex::new(p).ok());

    let mut stack: Vec<Context> = Vec::new();
    let mut path: Vec<PathSeg> = Vec::new();

    let mut matches_buffered: Vec<(Vec<PathSeg>, String)> = Vec::new();
    let mut match_count = 0;
    let mut has_more = false;

    let mut pop_path_if_needed = |stack: &mut Vec<Context>, path: &mut Vec<PathSeg>| {
        if let Some(ctx) = stack.last_mut() {
            match ctx {
                Context::Object { expecting_key } => {
                    if !*expecting_key {
                        path.pop();
                        *expecting_key = true;
                    }
                }
                Context::Array { .. } => {
                    path.pop();
                }
            }
        }
    };

    loop {
        skip_whitespace(&mut iter);
        let b = match iter.peek() {
            Some(Ok(b)) => *b,
            _ => break,
        };

        if let Some(ctx) = stack.last_mut() {
            match ctx {
                Context::Object { expecting_key } => {
                    if b == b'}' {
                        stack.pop();
                        iter.next();
                        pop_path_if_needed(&mut stack, &mut path);
                        continue;
                    }
                    if b == b',' {
                        iter.next();
                        continue;
                    }
                    if *expecting_key {
                        if b == b'"' {
                            let key = read_string(&mut iter, 1000);
                            *expecting_key = false;
                            path.push(PathSeg::Key(key));
                            skip_whitespace(&mut iter);
                            if let Some(Ok(b':')) = iter.peek() {
                                iter.next();
                            }
                            continue;
                        }
                        // unexpected
                        iter.next();
                        continue;
                    }
                }
                Context::Array { index } => {
                    if b == b']' {
                        stack.pop();
                        iter.next();
                        pop_path_if_needed(&mut stack, &mut path);
                        continue;
                    }
                    if b == b',' {
                        iter.next();
                        continue;
                    }
                    path.push(PathSeg::Index(*index));
                    *index += 1;
                }
            }
        }

        skip_whitespace(&mut iter);
        let b = match iter.peek() {
            Some(Ok(b)) => *b,
            _ => break,
        };

        let mut is_primitive = false;
        let mut val_str = String::new();

        if b == b'{' {
            stack.push(Context::Object { expecting_key: true });
            iter.next();
        } else if b == b'[' {
            stack.push(Context::Array { index: 0 });
            iter.next();
        } else if b == b'"' {
            let s = read_string(&mut iter, 1000);
            val_str = format!("\"{}\"", s);
            is_primitive = true;
        } else if b == b']' || b == b'}' {
            iter.next();
            stack.pop();
            pop_path_if_needed(&mut stack, &mut path);
        } else {
            val_str = read_primitive(&mut iter);
            if !val_str.is_empty() {
                is_primitive = true;
            } else {
                iter.next(); // unhandled character
            }
        }

        if is_primitive {
            let full_path_str = format_path(&path);
            let formatted_line = format!("{}: {}", full_path_str, val_str);
            
            let is_match = match &re {
                Some(r) => r.is_match(&formatted_line),
                None => true,
            };

            if is_match {
                if match_count >= offset {
                    if matches_buffered.len() < limit {
                        matches_buffered.push((path.clone(), val_str));
                    } else {
                        has_more = true;
                        break;
                    }
                }
                match_count += 1;
            }

            pop_path_if_needed(&mut stack, &mut path);
        }
    }

    let mut lcp_len = 0;
    if !matches_buffered.is_empty() {
        let first_path = &matches_buffered[0].0;
        lcp_len = first_path.len();
        for (p, _) in matches_buffered.iter().skip(1) {
            let mut matched_len = 0;
            for (a, b) in first_path.iter().zip(p.iter()) {
                if a == b {
                    matched_len += 1;
                } else {
                    break;
                }
            }
            lcp_len = std::cmp::min(lcp_len, matched_len);
        }
    }

    let lcp_str = if matches_buffered.is_empty() {
        "root".to_string()
    } else {
        format_path(&matches_buffered[0].0[..lcp_len])
    };

    let mut ordered_groups: Vec<(String, Vec<(String, String)>)> = Vec::new();

    for (p, val) in matches_buffered {
        let lcp_stripped = &p[lcp_len..];
        let mut parent_path = String::new();
        let mut prop_name = String::new();

        if lcp_stripped.is_empty() {
            prop_name = "".to_string();
        } else {
            let parent_len = lcp_stripped.len().saturating_sub(1);
            let parent_segs = &lcp_stripped[..parent_len];
            let last_seg = &lcp_stripped[parent_len];

            for seg in parent_segs {
                match seg {
                    PathSeg::Key(k) => {
                        if !parent_path.is_empty() {
                            parent_path.push('.');
                        }
                        parent_path.push_str(k);
                    }
                    PathSeg::Index(i) => {
                        parent_path.push('[');
                        parent_path.push_str(&i.to_string());
                        parent_path.push(']');
                    }
                }
            }

            match last_seg {
                PathSeg::Key(k) => {
                    prop_name = format!(".{}", k);
                }
                PathSeg::Index(i) => {
                    prop_name = format!("[{}]", i);
                }
            }
        }

        if let Some((last_parent, props)) = ordered_groups.last_mut() {
            if *last_parent == parent_path {
                props.push((prop_name, val));
                continue;
            }
        }
        ordered_groups.push((parent_path, vec![(prop_name, val)]));
    }

    let mut out = format!("# ⚡ TOON STREAM\n# CONTEXT: {}\n", lcp_str);
    if ordered_groups.is_empty() {
        out.push_str("(No matches found or EOF reached)\n");
    }

    for (parent, props) in ordered_groups {
        if !parent.is_empty() {
            out.push_str(&format!("\n[{}]\n", parent));
        } else {
            out.push_str("\n[.]\n");
        }
        for (prop, val) in props {
            if prop.is_empty() {
                out.push_str(&format!("= {}\n", val));
            } else {
                out.push_str(&format!("{}: {}\n", prop, val));
            }
        }
    }

    if has_more {
        out.push_str("\n--- [TRUNCATED: Use higher offset...] ---\n");
    }

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
