//! Transmutation MCP Proxy - Lightweight Wrapper
//!
//! Handles JSON-RPC over stdio and forwards to the persistent Transmutation Daemon.
//! Includes self-healing lifecycle management (auto-spawning the daemon).

use serde_json::{json, Value};
use std::time::{Duration, Instant};
use sysinfo::System;
use tokio::io::{self, AsyncBufReadExt, AsyncWriteExt, BufReader};
use reqwest::Client;

const DAEMON_URL: &str = "http://127.0.0.1:48192";
const DAEMON_BIN: &str = "daemon";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Setup minimal logging for the wrapper
    let log_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation").join("logs"))
        .unwrap_or_else(|| std::path::PathBuf::from("."));
    std::fs::create_dir_all(&log_dir).ok();
    
    let file_appender = tracing_appender::rolling::daily(log_dir, "mcp_proxy.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);
    
    tracing_subscriber::fmt()
        .with_writer(non_blocking)
        .with_target(false)
        .init();

    tracing::info!("MCP Proxy starting...");

    let client = Client::builder()
        .timeout(Duration::from_secs(300))
        .build()?;

    // 2. Self-Healing Lifecycle Management
    ensure_daemon_running(&client).await?;

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut reader = BufReader::new(stdin).lines();

    eprintln!("MCP Proxy ready. Waiting for JSON-RPC on stdin...");

    // 3. The MCP Event Loop
    while let Ok(Some(line)) = reader.next_line().await {
        tracing::info!("Received: {}", line);

        let req: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(e) => {
                tracing::error!("Failed to parse JSON-RPC: {}", e);
                continue;
            }
        };

        let method = req["method"].as_str().unwrap_or("");
        
        let id = match req.get("id") {
            Some(v) if !v.is_null() => v.clone(),
            _ => {
                tracing::info!("Skipping Notification '{}'", method);
                continue;
            }
        };

        let response = match method {
            "initialize" => {
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": { "tools": {} },
                        "serverInfo": { "name": "transmutation-secure-proxy", "version": "0.5.0" }
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
                            },
                            {
                                "name": "query_recon",
                                "description": "Day-One Call: Retrieve the top-level architectural clusters of the project (e.g., 'Where is the ML logic?').",
                                "inputSchema": { "type": "object", "properties": {} }
                            },
                            {
                                "name": "query_impact",
                                "description": "Blast Radius Call: See every file that will turn red if you modify a specific symbol (Trait, Struct, or Function).",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": { "symbol": { "type": "string" } },
                                    "required": ["symbol"]
                                }
                            },
                            {
                                "name": "query_discovery",
                                "description": "Needle-in-a-Haystack Call: Retrieve a focused Latent-K structural skeleton and code map for a specific file.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": { "filename": { "type": "string" } },
                                    "required": ["filename"]
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
                    match fetch_from_daemon(&client, "provenance", json!({ "request_id": req_id })).await {
                        Ok(res) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": res.content }], "isError": res.is_error } }),
                        Err(e) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": format!("Daemon Error: {}", e) }], "isError": true } }),
                    }
                } else if tool_name == "query_recon" {
                    match fetch_from_daemon(&client, "recon", json!({})).await {
                        Ok(res) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": res.content }], "isError": res.is_error } }),
                        Err(e) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": format!("Daemon Error: {}", e) }], "isError": true } }),
                    }
                } else if tool_name == "query_impact" {
                    let symbol = req["params"]["arguments"]["symbol"].as_str().unwrap_or("");
                    match fetch_from_daemon(&client, "impact", json!({ "symbol": symbol })).await {
                        Ok(res) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": res.content }], "isError": res.is_error } }),
                        Err(e) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": format!("Daemon Error: {}", e) }], "isError": true } }),
                    }
                } else if tool_name == "query_discovery" {
                    let filename = req["params"]["arguments"]["filename"].as_str().unwrap_or("");
                    match fetch_from_daemon(&client, "discovery", json!({ "filename": filename })).await {
                        Ok(res) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": res.content }], "isError": res.is_error } }),
                        Err(e) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": format!("Daemon Error: {}", e) }], "isError": true } }),
                    }
                } else {
                    let cmd = req["params"]["arguments"]["command"].as_str().unwrap_or("");
                    match forward_to_daemon(&client, cmd, tool_name).await {
                        Ok(res) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": res.content }], "isError": res.is_error } }),
                        Err(e) => json!({ "jsonrpc": "2.0", "id": id, "result": { "content": [{ "type": "text", "text": format!("Daemon Error: {}", e) }], "isError": true } }),
                    }
                }
            }
            _ => json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32601, "message": "Method not found" } }),
        };

        let mut out = serde_json::to_string(&response)?;
        tracing::debug!("Sending: {}", out);
        out.push('\n');
        stdout.write_all(out.as_bytes()).await?;
        stdout.flush().await?;
    }
    
    tracing::info!("MCP Proxy shutting down.");
    Ok(())
}

async fn fetch_from_daemon(client: &Client, endpoint: &str, payload: Value) -> Result<DaemonResponse, Box<dyn std::error::Error>> {
    let res = client.post(format!("{}/{}", DAEMON_URL, endpoint))
        .json(&payload)
        .send()
        .await?;
    
    let daemon_res: DaemonResponse = res.json().await?;
    Ok(daemon_res)
}

#[derive(serde::Deserialize)]
struct DaemonResponse {
    content: String,
    is_error: bool,
}

async fn forward_to_daemon(client: &Client, command: &str, tool_name: &str) -> Result<DaemonResponse, Box<dyn std::error::Error>> {
    let res = client.post(format!("{}/execute", DAEMON_URL))
        .json(&json!({ "command": command, "tool_name": tool_name }))
        .send()
        .await?;
    
    let daemon_res: DaemonResponse = res.json().await?;
    Ok(daemon_res)
}

async fn ensure_daemon_running(client: &Client) -> Result<(), Box<dyn std::error::Error>> {
    // 1. Check if it's already healthy
    if is_daemon_healthy(client).await {
        tracing::info!("Daemon is already running and healthy.");
        return Ok(());
    }

    tracing::warn!("Daemon not responding. Attempting cleanup and restart...");

    // 2. Kill any hung instances
    let mut sys = System::new_all();
    sys.refresh_all();
    for process in sys.processes_by_exact_name(std::ffi::OsStr::new(DAEMON_BIN)) {
        tracing::warn!("Killing hung daemon process: {}", process.pid());
        process.kill();
    }
    // Also try with .exe for Windows
    let bin_exe = format!("{}.exe", DAEMON_BIN);
    for process in sys.processes_by_exact_name(std::ffi::OsStr::new(&bin_exe)) {
        tracing::warn!("Killing hung daemon process: {}", process.pid());
        process.kill();
    }

    // Give the OS a moment to clean up ports
    tokio::time::sleep(Duration::from_millis(500)).await;

    // 3. Spawn the daemon
    // We assume the daemon binary is in the same directory as the proxy
    let current_exe = std::env::current_exe()?;
    let daemon_name = format!("{}{}", DAEMON_BIN, std::env::consts::EXE_SUFFIX);
    let daemon_path = current_exe.parent().unwrap().join(daemon_name);
    
    tracing::info!("Spawning new daemon from: {}", daemon_path.display());
    
    tokio::process::Command::new(&daemon_path)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()?;

    // 4. Wait for health (up to 5 seconds)
    let start = Instant::now();
    let timeout = Duration::from_secs(5);
    
    while start.elapsed() < timeout {
        if is_daemon_healthy(client).await {
            tracing::info!("Daemon successfully started and healthy.");
            return Ok(());
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    Err("Failed to start daemon within 5 seconds".into())
}

async fn is_daemon_healthy(client: &Client) -> bool {
    match client.get(format!("{}/health", DAEMON_URL))
        .timeout(Duration::from_millis(500))
        .send()
        .await 
    {
        Ok(res) => res.status().is_success(),
        Err(_) => false,
    }
}