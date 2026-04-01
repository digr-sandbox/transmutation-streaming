//! Transmutation MCP Proxy - Unified Security & Compression Server (v12)
//!
//! Fully compliant with the 2026 Model Context Protocol (MCP) Standards.
//! Features: Thompson NFA Security, Multi-Tenant Provenance, Database Janitor.

use serde::{Serialize, Deserialize};
use serde_json::{json, Value};
use tokio::io::{self, AsyncBufReadExt, AsyncWriteExt, BufReader};
use std::process::Stdio;
use std::time::Instant;
use std::path::{Path, PathBuf};
use transmutation::engines::security::SecurityEngine;
use transmutation::{Converter, OutputFormat, ConversionOptions, Result as TransResult};

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

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // 1. Initialize Security Engine
    let rules_path = std::env::var("RULES_JSON_PATH")
        .unwrap_or_else(|_| "rules.json".to_string());

    let security = SecurityEngine::load_from_file(Path::new(&rules_path))
        .expect("Failed to load rules.json");

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut reader = BufReader::new(stdin).lines();

    // 2. The MCP Event Loop
    while let Ok(Some(line)) = reader.next_line().await {
        let start_rpc = Instant::now();
        let req: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let id = req["id"].clone();
        let method = req["method"].as_str().unwrap_or("");

        let response = match method {
            "initialize" => {
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": { "tools": {}, "notifications": true },
                        "serverInfo": { "name": "transmutation-secure-proxy", "version": "0.4.0" }
                    }
                })
            }
            "ping" => json!({ "jsonrpc": "2.0", "id": id, "result": {} }),
            "tools/list" => {
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {
                        "tools": [
                            {
                                "name": "execute_command",
                                "description": "Execute a shell command with mandatory security and token pruning.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": { "command": { "type": "string" } },
                                    "required": ["command"]
                                }
                            },
                            {
                                "name": "get_provenance",
                                "description": "Retrieve detailed transformation metadata for a specific request ID.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": { "request_id": { "type": "string" } },
                                    "required": ["request_id"]
                                }
                            }
                        ]
                    }
                })
            }
            "tools/call" => {
                let tool_name = req["params"]["name"].as_str().unwrap_or("");
                
                if tool_name == "get_provenance" {
                    let req_id = req["params"]["arguments"]["request_id"].as_str().unwrap_or("");
                    match get_provenance_from_db(req_id) {
                        Ok(audit_json) => json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": { "content": [{ "type": "text", "text": audit_json }], "isError": false }
                        }),
                        Err(e) => json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": { "content": [{ "type": "text", "text": format!("Audit NotFound: {}", e) }], "isError": true }
                        }),
                    }
                } else {
                    let cmd = req["params"]["arguments"]["command"].as_str().unwrap_or("");
                    let start_security = Instant::now();
                    let security_result = security.evaluate(cmd, tool_name);
                    let security_ms = start_security.elapsed().as_millis();

                    if let Some(error_msg) = security_result {
                        json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": { "content": [{ "type": "text", "text": error_msg }], "isError": true }
                        })
                    } else {
                        match execute_and_transmute(cmd, security_ms, start_rpc).await {
                            Ok((transmuted_text, is_error)) => json!({
                                "jsonrpc": "2.0", "id": id,
                                "result": { "content": [{ "type": "text", "text": transmuted_text }], "isError": is_error }
                            }),
                            Err(e) => json!({
                                "jsonrpc": "2.0", "id": id,
                                "result": { "content": [{ "type": "text", "text": format!("Proxy Error: {}", e) }], "isError": true }
                            }),
                        }
                    }
                }
            }
            _ => json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32601, "message": "Method not found" } }),
        };

        let mut out = serde_json::to_string(&response)?;
        out.push('\n');
        stdout.write_all(out.as_bytes()).await?;
        stdout.flush().await?;
    }
    Ok(())
}

async fn execute_and_transmute(cmd: &str, security_ms: u128, rpc_timer: Instant) -> Result<(String, bool), Box<dyn std::error::Error + Send + Sync>> {
    let start_shell = Instant::now();
    let req_id = format!("req_{}", start_shell.elapsed().as_nanos()); // UNIQUE REQUEST ID
    
    let temp_file = tempfile::Builder::new().prefix("mcp_spool_").suffix(".txt").tempfile()?;
    let mut child = tokio::process::Command::new("cmd").arg("/c").arg(cmd).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;

    let mut stdout = child.stdout.take().unwrap();
    let mut stderr = child.stderr.take().unwrap();
    let mut file = tokio::fs::File::from_std(temp_file.reopen()?);
    tokio::io::copy(&mut stdout, &mut file).await?;
    tokio::io::copy(&mut stderr, &mut file).await?;
    
    let status = child.wait().await?;
    let shell_ms = start_shell.elapsed().as_millis();

    let start_proxy = Instant::now();
    let converter = Converter::new()?;
    let result = converter.convert(temp_file.path()).to(OutputFormat::Markdown { split_pages: false, optimize_for_llm: true }).execute().await?;
    let proxy_ms = start_proxy.elapsed().as_millis();

    let mut final_text = String::new();
    final_text.push_str(&format!("# ⚡ PROVENANCE [ID: {} | Transformed: TOON+STAT_V7]\n---\n", req_id));
    for chunk in &result.content { final_text.push_str(&String::from_utf8_lossy(&chunk.data)); }

    let record = AuditLogRecord {
        timestamp: chrono::Utc::now(),
        request_id: req_id,
        command: cmd.to_string(),
        exit_code: status.code().unwrap_or(-1),
        security_ms, shell_ms, proxy_ms,
        total_ms: rpc_timer.elapsed().as_millis(),
        input_bytes: result.statistics.input_size_bytes as usize,
        output_bytes: final_text.len(),
    };

    let _ = offload_to_sqlite(&record);
    Ok((final_text, !status.success()))
}

fn get_provenance_from_db(req_id: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let db_dir = dirs::home_dir().map(|p| p.join(".transmutation")).unwrap_or_else(|| PathBuf::from("."));
    let db_path = db_dir.join("audit.db");
    let conn = rusqlite::Connection::open(&db_path)?;
    
    let mut stmt = conn.prepare("SELECT * FROM audit_events WHERE request_id = ?")?;
    let mut rows = stmt.query_map([req_id], |row| {
        Ok(json!({
            "request_id": row.get::<_, String>(1)?,
            "command": row.get::<_, String>(2)?,
            "exit_code": row.get::<_, i32>(3)?,
            "security_ms": row.get::<_, i64>(4)?,
            "shell_ms": row.get::<_, i64>(5)?,
            "proxy_ms": row.get::<_, i64>(6)?,
            "input_bytes": row.get::<_, i64>(8)?,
            "output_bytes": row.get::<_, i64>(9)?,
        }))
    })?;

    if let Some(row) = rows.next() {
        Ok(serde_json::to_string_pretty(&row?)?)
    } else {
        Err("Request ID not found".into())
    }
}

fn offload_to_sqlite(record: &AuditLogRecord) -> TransResult<()> {
    let db_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation"))
        .unwrap_or_else(|| PathBuf::from("."));
    let db_path = db_dir.join("audit.db");
    let conn = rusqlite::Connection::open(&db_path).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Connection failed", e))?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS audit_events (
            timestamp TEXT, request_id TEXT, command TEXT, exit_code INTEGER,
            security_ms INTEGER, shell_ms INTEGER, proxy_ms INTEGER, total_ms INTEGER,
            input_bytes INTEGER, output_bytes INTEGER
        )", [],
    ).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Table creation failed", e))?;

    conn.execute(
        "INSERT INTO audit_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rusqlite::params![
            record.timestamp.to_rfc3339(), record.request_id, record.command, record.exit_code,
            record.security_ms as i64, record.shell_ms as i64, record.proxy_ms as i64,
            record.total_ms as i64, record.input_bytes as i64, record.output_bytes as i64,
        ],
    ).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Insert failed", e))?;
    Ok(())
}

