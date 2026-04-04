//! Transmutation Persistent Daemon
//!
//! Handles long-running state: Security Engine caching, File Watching (Latent-K),
//! and SQLite audit locks. Listens on a local HTTP port.

use axum::{
    routing::{get, post},
    Router, Json, extract::State,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::path::{Path, PathBuf};
use std::time::Instant;
use std::process::Stdio;
use std::collections::HashSet;
use tokio::net::TcpListener;
use transmutation::engines::security::SecurityEngine;
use transmutation::{Converter, OutputFormat, Result as TransResult};
use rusqlite::Connection;
use walkdir::WalkDir;
use regex::Regex;

struct CodeMapEngine {
    conn: std::sync::Mutex<Connection>,
}

impl CodeMapEngine {
    fn new() -> Self {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute("CREATE TABLE edges (source TEXT, target TEXT, UNIQUE(source, target))", []).unwrap();
        conn.execute("CREATE TABLE symbols (file TEXT, name TEXT, UNIQUE(file, name))", []).unwrap();
        Self { conn: std::sync::Mutex::new(conn) }
    }

    fn extract_data(content: &str, file_path: &str) -> (HashSet<String>, HashSet<String>) {
        let mut edges = HashSet::new();
        let mut symbols = HashSet::new();
        
        let rust_import_re = Regex::new(r"use\s+crate::([a-zA-Z0-9_:]+)").unwrap();
        let rust_mod_re = Regex::new(r"pub\s+mod\s+([a-zA-Z0-9_]+)").unwrap();
        let rust_symbol_re = Regex::new(r"pub\s+(struct|enum|trait|type|fn)\s+([a-zA-Z0-9_]+)").unwrap();
        
        for cap in rust_import_re.captures_iter(content) {
            let mut path = "src".to_string();
            for part in cap[1].split("::") {
                if part == "*" || part.starts_with('{') { break; }
                path.push('/'); path.push_str(part);
            }
            edges.insert(format!("{}.rs", path));
            edges.insert(format!("{}/mod.rs", path));
        }

        for cap in rust_mod_re.captures_iter(content) {
            let parent = Path::new(file_path).parent().unwrap().to_string_lossy().replace("\\", "/");
            edges.insert(format!("{}/{}.rs", parent, &cap[1]));
            edges.insert(format!("{}/{}/mod.rs", parent, &cap[1]));
        }

        for cap in rust_symbol_re.captures_iter(content) {
            symbols.insert(cap[2].to_string());
        }

        (edges.into_iter().filter(|p| Path::new(p).exists()).collect(), symbols)
    }

    fn build_initial_map(&self) {
        let mut all_data = Vec::new();
        for entry in WalkDir::new("src").into_iter().filter_map(|e| e.ok()) {
            if entry.path().extension().map_or(false, |ext| ext == "rs") {
                let source = entry.path().to_string_lossy().replace("\\", "/");
                if let Ok(content) = std::fs::read_to_string(entry.path()) {
                    let (edges, symbols) = Self::extract_data(&content, &source);
                    all_data.push((source, edges, symbols));
                }
            }
        }
        
        let conn = self.conn.lock().unwrap();
        for (source, edges, symbols) in all_data {
            for target in edges {
                let _ = conn.execute("INSERT OR IGNORE INTO edges (source, target) VALUES (?1, ?2)", rusqlite::params![source, target]);
            }
            for sym in symbols {
                let _ = conn.execute("INSERT OR IGNORE INTO symbols (file, name) VALUES (?1, ?2)", rusqlite::params![source, sym]);
            }
        }
    }

    fn read_code_map(&self, filename: &str) -> String {
        let mut imports_from = Vec::new();
        let mut imported_by = Vec::new();
        let conn = self.conn.lock().unwrap();

        if let Ok(mut stmt) = conn.prepare("SELECT target FROM edges WHERE source = ?1") {
            if let Ok(rows) = stmt.query_map([filename], |row| row.get::<_, String>(0)) {
                for r in rows.flatten() { imports_from.push(r); }
            }
        }

        if let Ok(mut stmt2) = conn.prepare("SELECT source FROM edges WHERE target = ?1") {
            if let Ok(rows) = stmt2.query_map([filename], |row| row.get::<_, String>(0)) {
                for r in rows.flatten() { imported_by.push(r); }
            }
        }

        let mut out = format!("[ARCHITECTURE CODE MAP]\nFile: {}\n", filename);
        out.push_str("Imports From: ");
        if imports_from.is_empty() { out.push_str("(None)\n"); } else { out.push_str(&imports_from.join(", ")); out.push('\n'); }
        out.push_str("Imported By: ");
        if imported_by.is_empty() { out.push_str("(None)\n"); } else { out.push_str(&imported_by.join(", ")); out.push('\n'); }
        out
    }

    fn query_recon(&self) -> String {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT DISTINCT source FROM edges").unwrap();
        let rows = stmt.query_map([], |row| row.get::<_, String>(0)).unwrap();
        
        let mut clusters: HashMap<String, Vec<String>> = HashMap::new();
        for path in rows.flatten() {
            let parts: Vec<&str> = path.split('/').collect();
            if parts.len() > 1 {
                clusters.entry(parts[..parts.len()-1].join("/")).or_default().push(parts.last().unwrap().to_string());
            }
        }

        let mut out = "[ARCHITECTURAL RECONNAISSANCE]\n".to_string();
        for (dir, files) in clusters {
            out.push_str(&format!("- {}: [{} files]\n", dir, files.len()));
        }
        out
    }

    fn query_impact(&self, symbol: &str) -> String {
        let conn = self.conn.lock().unwrap();
        
        // 1. Find who defines the symbol
        let mut stmt_def = conn.prepare("SELECT file FROM symbols WHERE name = ?1").unwrap();
        let def_files: Vec<String> = stmt_def.query_map([symbol], |row| row.get(0)).unwrap().flatten().collect();
        
        let mut affected = HashSet::new();
        
        // 2. Find who imports those files
        for f in &def_files {
            let mut stmt_imp = conn.prepare("SELECT source FROM edges WHERE target = ?1").unwrap();
            let rows = stmt_imp.query_map([f], |row| row.get::<_, String>(0)).unwrap();
            for r in rows.flatten() { affected.insert(r); }
        }

        // 3. Fallback: Search all files for mentions of the symbol (excluding definitions)
        for entry in WalkDir::new("src").into_iter().filter_map(|e| e.ok()) {
            if entry.path().extension().map_or(false, |ext| ext == "rs") {
                let path = entry.path().to_string_lossy().replace("\\", "/");
                if def_files.contains(&path) { continue; }
                if let Ok(content) = std::fs::read_to_string(entry.path()) {
                    if content.contains(symbol) {
                        affected.insert(path);
                    }
                }
            }
        }
        
        let mut out = format!("[BLAST RADIUS: {}]\nDefined in: {}\nFiles affected:\n", 
            symbol, if def_files.is_empty() { "(Unknown)".to_string() } else { def_files.join(", ") });
        
        if affected.is_empty() {
            out.push_str("  (No usage found)\n");
        } else {
            for path in affected {
                out.push_str(&format!("  - {}\n", path));
            }
        }
        out
    }
}

use std::collections::HashMap;

#[derive(Serialize, Deserialize, Debug)]
struct AuditLogRecord {
    timestamp: chrono::DateTime<chrono::Utc>,
    request_id: String,
    command: String,
    exit_code: i32,
    security_ms: u128,
    shell_ms: u128,
    proxy_ms: u128,
    total_ms: u128,
    input_bytes: usize,
    output_bytes: usize,
}

#[derive(Deserialize)]
struct ExecuteRequest {
    command: String,
    tool_name: String,
}

#[derive(Serialize)]
struct ExecuteResponse {
    content: String,
    is_error: bool,
}

#[derive(Deserialize)]
struct ProvenanceRequest {
    request_id: String,
}

#[derive(Serialize)]
struct ProvenanceResponse {
    content: String,
    is_error: bool,
}

#[derive(Deserialize)]
struct CodeMapRequest {
    filename: String,
}

#[derive(Deserialize)]
struct ImpactRequest {
    symbol: String,
}

#[derive(Serialize)]
struct GenericResponse {
    content: String,
    is_error: bool,
}

struct AppState {
    security: SecurityEngine,
    code_map: Arc<CodeMapEngine>,
}

#[tokio::main]
async fn main() {
    let log_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap_or_else(|| PathBuf::from("."));
    std::fs::create_dir_all(&log_dir).ok();
    let file_appender = tracing_appender::rolling::daily(log_dir, "daemon.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);
    tracing_subscriber::fmt().with_writer(non_blocking).with_target(false).init();

    tracing::info!("Starting Transmutation Daemon...");

    let security = match std::env::var("RULES_JSON_PATH") {
        Ok(path) => SecurityEngine::load_from_file(Path::new(&path)).unwrap(),
        Err(_) => {
            if let Ok(sec) = SecurityEngine::load_from_file(Path::new("rules.json")) { sec }
            else { SecurityEngine::load_from_str(include_str!("../../rules.json")).unwrap() }
        }
    };

    let code_map = Arc::new(CodeMapEngine::new());
    
    let code_map_clone = code_map.clone();
    tokio::task::spawn_blocking(move || {
        code_map_clone.build_initial_map();
    });

    let state = Arc::new(AppState { security, code_map });

    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/execute", post(handle_execute))
        .route("/provenance", post(handle_provenance))
        .route("/recon", post(handle_recon))
        .route("/impact", post(handle_impact))
        .route("/discovery", post(handle_discovery))
        .with_state(state);

    let listener = TcpListener::bind("127.0.0.1:48192").await.unwrap();
    tracing::info!("Daemon listening on 127.0.0.1:48192");
    axum::serve(listener, app).await.unwrap();
}

async fn handle_recon(State(state): State<Arc<AppState>>) -> Json<GenericResponse> {
    Json(GenericResponse { content: state.code_map.query_recon(), is_error: false })
}

async fn handle_impact(State(state): State<Arc<AppState>>, Json(payload): Json<ImpactRequest>) -> Json<GenericResponse> {
    Json(GenericResponse { content: state.code_map.query_impact(&payload.symbol), is_error: false })
}

async fn handle_discovery(State(state): State<Arc<AppState>>, Json(payload): Json<CodeMapRequest>) -> Json<GenericResponse> {
    // Merge Code Map with Latent-K Summary
    let map = state.code_map.read_code_map(&payload.filename);
    let content = std::fs::read_to_string(&payload.filename).unwrap_or_default();
    let skeleton = structural_extraction(&content);
    
    Json(GenericResponse { 
        content: format!("{}\n\n[STRUCTURAL SKELETON (Latent-K)]\n{}", map, skeleton), 
        is_error: false 
    })
}

fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_import = false;
    let mut depth = 0;
    let mut in_structural = false;

    let boredom_table: HashSet<&str> = [
        "if", "else", "let", "var", "const", "return", "public", "private", "protected", 
        "class", "function", "fn", "void", "int", "char", "string", "bool", "true", "false", 
        "import", "from", "use", "include", "struct", "impl", "type", "interface", "package", 
        "namespace", "static", "async", "await", "try", "catch", "throw", "new", "delete", 
        "this", "self", "super", "for", "while", "do", "switch", "case", "default", "break", 
        "continue", "in", "of", "as", "is"
    ].iter().cloned().collect();

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() { continue; }
        
        // --- PASS 0: ABSOLUTE COMMENT EVICTION ---
        if (trimmed.starts_with("//") || trimmed.starts_with('#') || trimmed.starts_with("/*") || 
            trimmed.starts_with('*') || trimmed.starts_with('%') || trimmed.starts_with("--")) 
           && !trimmed.contains('@') && !trimmed.contains("#[") {
            continue;
        }
        if trimmed.contains("JUNK_") || trimmed.contains("LICENSE_HEADER") || trimmed.contains("boilerplate") {
            continue;
        }

        // --- PASS 1: IMPORT ANCHORING ---
        if trimmed.starts_with("import ") || trimmed.starts_with("use ") || trimmed.starts_with("#include") || 
           trimmed.starts_with("package ") || trimmed.starts_with("-module") || trimmed.starts_with("require") {
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

        // --- PASS 2: DEPTH TRACKING ---
        let open_braces = trimmed.chars().filter(|&c| c == '{').count();
        let close_braces = trimmed.chars().filter(|&c| c == '}').count();
        let was_at_root = depth == 0;
        
        // Update depth tracking based on block type
        let is_structural = trimmed.contains("struct") || trimmed.contains("typedef") || 
                           trimmed.contains("interface") || trimmed.contains("enum") ||
                           trimmed.to_uppercase().contains("TABLE") ||
                           trimmed.starts_with("type ") || trimmed.starts_with("query ") || 
                           trimmed.starts_with("mutation ") || trimmed.starts_with("BEGIN");
        
        if is_structural { in_structural = true; }
        
        // --- PASS 3: WEIGHTED SIGNAL SCORING ---
        let mut score = 0;

        // Meta-Gravity
        if trimmed.starts_with('@') || trimmed.starts_with("#[") || trimmed.starts_with("#!") || 
           trimmed.starts_with("<?php") || trimmed.starts_with("-module") {
            score += 30;
        }
        
        // Structural Gravity (Signatures)
        if trimmed.ends_with('{') || trimmed.ends_with(':') || trimmed.ends_with('[') || 
           is_structural || (trimmed.contains("func ") && !trimmed.contains('}')) || 
           trimmed.contains("::") || trimmed.contains("->") {
            score += 20;
        }

        // Data & Protocol Gravity
        if trimmed.starts_with('+') || trimmed.starts_with('-') || trimmed.starts_with('>') || 
           trimmed.to_uppercase().contains("INSERT ") || trimmed.to_uppercase().contains("SELECT ") || 
           trimmed.to_uppercase().contains("UPDATE ") || trimmed.to_uppercase().contains("PRIMARY KEY") ||
           trimmed.to_uppercase().contains("BEGIN") || trimmed.to_uppercase().contains("COMMIT") {
            score += 20;
        }

        // Flow Control & Memory Management
        if trimmed.contains("await") || trimmed.contains("return") || trimmed.contains("throw") || 
           trimmed.contains("yield") || trimmed.contains("yield*") || trimmed.contains("malloc") || 
           trimmed.contains("free") || trimmed.contains("strdup") || trimmed.contains("new ") {
            score += 15;
        }

        // Relational Gravity (Chains, Pointers, Keys, Refs)
        if trimmed.contains("->") || trimmed.contains('*') || trimmed.contains('&') ||
           (trimmed.contains('.') && (trimmed.contains('(') || trimmed.contains('['))) ||
           (trimmed.contains(':') && !trimmed.contains('{')) {
            score += 10;
        }

        // Information Density (Boredom Check)
        let has_high_signal = trimmed.split(|c: char| !c.is_alphanumeric() && c != '@' && c != '_')
            .any(|token| {
                if token.is_empty() || boredom_table.contains(token.to_lowercase().as_str()) { return false; }
                let has_upper = token.chars().any(|c| c.is_uppercase());
                let has_lower = token.chars().any(|c| c.is_lowercase());
                token.len() > 2 && (has_upper && has_lower || token.contains('_') || token.ends_with('*') || token.chars().all(|c| c.is_uppercase()))
            });
        
        if has_high_signal {
            score += 5;
        }

        // --- PASS 4: TIERED PRESERVATION ---
        // Threshold 1 for root and structural definitions (schemas/interfaces)
        // Threshold 10 for implementation bodies (sweet spot for C/TS logic)
        let threshold = if was_at_root || in_structural { 1 } else { 10 };

        if score >= threshold {
            // Never collapse signatures that have parameters (parentheses) or schema fields (colons)
            let is_complex_line = trimmed.contains('(') || (trimmed.contains(':') && !trimmed.contains('{'));
            if was_at_root && trimmed.ends_with('{') && !is_complex_line && !is_structural {
                lines.push(format!("{} ... }}", line.trim_end_matches('{').trim_end()));
            } else {
                lines.push(line.to_string());
            }
        }

        depth = depth + open_braces as i32 - close_braces as i32;
        if depth <= 0 { depth = 0; in_structural = false; }
    }
    lines.join("\n")
}

async fn handle_execute(State(state): State<Arc<AppState>>, Json(payload): Json<ExecuteRequest>) -> Json<ExecuteResponse> {
    let start_rpc = Instant::now();
    let start_security = Instant::now();
    let platform = std::env::consts::OS;
    let security_result = state.security.evaluate(&payload.command, &payload.tool_name, platform);
    let security_ms = start_security.elapsed().as_millis();

    if let Some(error_msg) = security_result {
        return Json(ExecuteResponse { content: error_msg, is_error: true });
    }

    match execute_secure_command(&payload.command, security_ms, start_rpc).await {
        Ok((output_text, is_error)) => Json(ExecuteResponse { content: output_text, is_error }),
        Err(e) => Json(ExecuteResponse { content: format!("Proxy Error: {}", e), is_error: true })
    }
}

async fn handle_provenance(Json(payload): Json<ProvenanceRequest>) -> Json<GenericResponse> {
    match get_provenance_from_db(&payload.request_id) {
        Ok(audit_json) => Json(GenericResponse { content: audit_json, is_error: false }),
        Err(e) => Json(GenericResponse { content: format!("Audit NotFound: {}", e), is_error: true })
    }
}

async fn execute_secure_command(cmd: &str, security_ms: u128, rpc_timer: Instant) -> Result<(String, bool), Box<dyn std::error::Error + Send + Sync>> {
    let start_shell = Instant::now();
    let req_id = format!("req_{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos());
    let temp_file = tempfile::Builder::new().prefix("mcp_spool_").suffix(".txt").tempfile()?;
    let mut child = tokio::process::Command::new("cmd").arg("/c").arg(cmd).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;
    let mut stdout = child.stdout.take().unwrap();
    let mut stderr = child.stderr.take().unwrap();
    let mut file = tokio::fs::File::from_std(temp_file.reopen()?);
    tokio::io::copy(&mut stdout, &mut file).await?;
    tokio::io::copy(&mut stderr, &mut file).await?;
    let status = child.wait().await?;
    let shell_ms = start_shell.elapsed().as_millis();
    let raw_input = std::fs::read_to_string(temp_file.path()).unwrap_or_default();
    
    let record = AuditLogRecord { timestamp: chrono::Utc::now(), request_id: req_id, command: cmd.to_string(), exit_code: status.code().unwrap_or(-1), security_ms, shell_ms, proxy_ms: 0, total_ms: rpc_timer.elapsed().as_millis(), input_bytes: raw_input.len(), output_bytes: raw_input.len() };
    if let Err(e) = offload_to_sqlite(&record, &raw_input, &raw_input) { tracing::error!("Failed to save audit log to SQLite: {}", e); }
    Ok((raw_input, !status.success()))
}

fn get_provenance_from_db(req_id: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let db_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap_or_else(|| PathBuf::from("."));
    let db_path = db_dir.join("audit.db");
    let conn = rusqlite::Connection::open(&db_path)?;
    let mut stmt = conn.prepare("SELECT e.*, c.raw_input, c.final_output FROM audit_events e JOIN audit_content c ON e.request_id = c.request_id WHERE e.request_id = ?")?;
    let mut rows = stmt.query_map([req_id], |row| Ok(serde_json::json!({ 
        "request_id": row.get::<_, String>(0)?, 
        "timestamp": row.get::<_, String>(1)?, 
        "command": row.get::<_, String>(2)?, 
        "exit_code": row.get::<_, i32>(3)?, 
        "security_ms": row.get::<_, i64>(4)?, 
        "shell_ms": row.get::<_, i64>(5)?, 
        "proxy_ms": row.get::<_, i64>(6)?, 
        "total_ms": row.get::<_, i64>(7)?, 
        "input_bytes": row.get::<_, i64>(8)?, 
        "output_bytes": row.get::<_, i64>(9)?, 
        "raw_input_preview": row.get::<_, String>(10)?.chars().take(500).collect::<String>(), 
        "final_output_preview": row.get::<_, String>(11)?.chars().take(500).collect::<String>(), 
    })))?;
    if let Some(row) = rows.next() { Ok(serde_json::to_string_pretty(&row?)?) } else { Err("Request ID not found".into()) }
}

fn offload_to_sqlite(record: &AuditLogRecord, raw_input: &str, final_output: &str) -> TransResult<()> {
    let db_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap_or_else(|| PathBuf::from("."));
    let db_path = db_dir.join("audit.db");
    let mut conn = rusqlite::Connection::open(&db_path).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Connection failed", e))?;
    let tx = conn.transaction().map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "TX start failed", e))?;
    tx.execute("CREATE TABLE IF NOT EXISTS audit_events (request_id TEXT PRIMARY KEY, timestamp TEXT, command TEXT, exit_code INTEGER, security_ms INTEGER, shell_ms INTEGER, proxy_ms INTEGER, total_ms INTEGER, input_bytes INTEGER, output_bytes INTEGER )", []).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Header table failed", e))?;
    tx.execute("CREATE TABLE IF NOT EXISTS audit_content (request_id TEXT PRIMARY KEY, raw_input TEXT, final_output TEXT, FOREIGN KEY(request_id) REFERENCES audit_events(request_id) )", []).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Content table failed", e))?;
    tx.execute("INSERT INTO audit_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", rusqlite::params![ record.request_id, record.timestamp.to_rfc3339(), record.command, record.exit_code, record.security_ms as i64, record.shell_ms as i64, record.proxy_ms as i64, record.total_ms as i64, record.input_bytes as i64, record.output_bytes as i64, ],).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Header insert failed", e))?;
    tx.execute("INSERT INTO audit_content VALUES (?, ?, ?)", rusqlite::params![ record.request_id, raw_input, final_output, ],).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Content insert failed", e))?;
    tx.commit().map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "TX commit failed", e))?;
    Ok(())
}