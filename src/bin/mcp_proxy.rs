//! Transmutation MCP Proxy - Unified Security & Compression Server
//!
//! Provides an MCP (Model Context Protocol) interface for agentic tools.
//! Mandatory Security: THOMPSON NFA Rule Engine
//! Mandatory Compression: TOON + Statistical Pruning (v7)

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
    command: String,
    exit_code: i32,
    security_ms: u128,   // NEW: Time spent in Thompson NFA
    shell_ms: u128,      // Child process duration
    proxy_ms: u128,      // Transmutation/Pruning duration
    total_ms: u128,      // NEW: Total JSON-RPC roundtrip time
    input_bytes: usize,
    output_bytes: usize,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // 1. Initialize Security Engine
    let rules_path = std::env::var("RULES_JSON_PATH")
        .unwrap_or_else(|_| "rules.json".to_string());

    let security = SecurityEngine::load_from_file(Path::new(&rules_path))
        .expect("Failed to load rules.json for security sandbox");

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut reader = BufReader::new(stdin).lines();

    // 2. The MCP Event Loop
    while let Ok(Some(line)) = reader.next_line().await {
        let start_rpc = Instant::now(); // START RPC TIMER
        
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
                        "capabilities": { "tools": {} },
                        "serverInfo": { "name": "transmutation-secure-proxy", "version": "0.4.0" }
                    }
                })
            }
            "ping" => {
                // MCP 2026: Response must be an empty object
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {}
                })
            }
            "tools/list" => {
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {
                        "tools": [{
                            "name": "execute_command",
                            "description": "Run a shell command. Mandatory security and context optimization are active.",
                            "inputSchema": {
                                "type": "object",
                                "properties": { "command": { "type": "string" } },
                                "required": ["command"]
                            }
                        }]
                    }
                })
            }
            "tools/call" => {
                let tool_name = req["params"]["name"].as_str().unwrap_or("");
                let cmd = req["params"]["arguments"]["command"].as_str().unwrap_or("");

                // LAYER 1: Mandatory Security Interception (Timed)
                let start_security = Instant::now();
                let security_result = security.evaluate(cmd, tool_name);
                let security_ms = start_security.elapsed().as_millis();

                if let Some(error_msg) = security_result {
                    json!({
                        "jsonrpc": "2.0",
                        "id": id,
                        "result": {
                            "content": [{ "type": "text", "text": error_msg }],
                            "isError": true
                        }
                    })
                } else {
                    // LAYER 2 & 3: Execute and Transmute
                    match execute_and_transmute(cmd, security_ms, start_rpc).await {
                        Ok((transmuted_text, is_error)) => {
                            json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "result": {
                                    "content": [{ "type": "text", "text": transmuted_text }],
                                    "isError": is_error
                                }
                            })
                        }
                        Err(e) => {
                            json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "result": {
                                    "content": [{ "type": "text", "text": format!("Proxy Error: {}", e) }],
                                    "isError": true
                                }
                            })
                        }
                    }
                }
            }
            _ => json!({ "jsonrpc": "2.0", "id": id, "result": null }),
        };

        let mut out = serde_json::to_string(&response)?;
        out.push('\n');
        stdout.write_all(out.as_bytes()).await?;
        stdout.flush().await?;
    }

    Ok(())
}

async fn execute_and_transmute(
    cmd: &str, 
    security_ms: u128, 
    rpc_timer: Instant
) -> Result<(String, bool), Box<dyn std::error::Error + Send + Sync>> {
    let start_shell = Instant::now();
    
    // Create temporary spool file
    let temp_file = tempfile::Builder::new()
        .prefix("mcp_spool_")
        .suffix(".txt")
        .tempfile()?;
    
    // Spawn shell
    let mut child = tokio::process::Command::new("cmd")
        .arg("/c")
        .arg(cmd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let mut stdout = child.stdout.take().unwrap();
    let mut stderr = child.stderr.take().unwrap();
    
    // Spool to disk (OOM-Safe)
    let mut file = tokio::fs::File::from_std(temp_file.reopen()?);
    tokio::io::copy(&mut stdout, &mut file).await?;
    tokio::io::copy(&mut stderr, &mut file).await?;
    
    let status = child.wait().await?;
    let shell_ms = start_shell.elapsed().as_millis();

    // LAYER 3: Mandatory Transmutation
    let start_proxy = Instant::now();
    let converter = Converter::new()?;
    let options = ConversionOptions {
        optimize_for_llm: true,
        ..Default::default()
    };

    let result = converter
        .convert(temp_file.path())
        .to(OutputFormat::Markdown { split_pages: false, optimize_for_llm: true })
        .with_options(options)
        .execute()
        .await?;

    let proxy_ms = start_proxy.elapsed().as_millis();

    // Merging output
    let mut final_text = String::new();
    final_text.push_str("# ⚡ PROVENANCE [V: 0.4.0 | Src: STDOUT | Transformed: TOON+STAT_V7]\n---\n");
    for chunk in &result.content {
        final_text.push_str(&String::from_utf8_lossy(&chunk.data));
    }

    // LAYER 4: Audit Persistence (Header Log)
    let record = AuditLogRecord {
        timestamp: chrono::Utc::now(),
        command: cmd.to_string(),
        exit_code: status.code().unwrap_or(-1),
        security_ms,
        shell_ms,
        proxy_ms,
        total_ms: rpc_timer.elapsed().as_millis(),
        input_bytes: result.statistics.input_size_bytes as usize,
        output_bytes: final_text.len(),
    };

    if let Err(e) = offload_to_sqlite(&record) {
        eprintln!("WARN: Audit logging failed: {}", e);
    }

    Ok((final_text, !status.success()))
}

fn offload_to_sqlite(record: &AuditLogRecord) -> TransResult<()> {
    let db_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation"))
        .unwrap_or_else(|| PathBuf::from("."));
    
    std::fs::create_dir_all(&db_dir).map_err(|e| transmutation::TransmutationError::IoError(e))?;
    let db_path = db_dir.join("audit.db");

    // Purge logic (1GB Budget)
    if let Ok(metadata) = std::fs::metadata(&db_path) {
        if metadata.len() > 1000 * 1024 * 1024 {
            let conn = rusqlite::Connection::open(&db_path)
                .map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Connection failed", e))?;
            let _ = conn.execute("DELETE FROM audit_events WHERE timestamp IN (SELECT timestamp FROM audit_events ORDER BY timestamp ASC LIMIT 500)", []);
            let _ = conn.execute("VACUUM", []);
        }
    }

    let conn = rusqlite::Connection::open(&db_path)
        .map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Connection failed", e))?;

    // Create schema with new columns for v11
    conn.execute(
        "CREATE TABLE IF NOT EXISTS audit_events_v11 (
            timestamp TEXT,
            command TEXT,
            exit_code INTEGER,
            security_ms INTEGER,
            shell_ms INTEGER,
            proxy_ms INTEGER,
            total_ms INTEGER,
            input_bytes INTEGER,
            output_bytes INTEGER
        )",
        [],
    ).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Table creation failed", e))?;

    conn.execute(
        "INSERT INTO audit_events_v11 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rusqlite::params![
            record.timestamp.to_rfc3339(),
            record.command,
            record.exit_code,
            record.security_ms as i64,
            record.shell_ms as i64,
            record.proxy_ms as i64,
            record.total_ms as i64,
            record.input_bytes as i64,
            record.output_bytes as i64,
        ],
    ).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Insert failed", e))?;

    Ok(())
}
