//! Transmutation Persistent Daemon
//!
//! Handles long-running state: Security Engine caching, File Watching (Latent-K),
//! and SQLite audit locks. Listens on a local HTTP port.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use std::time::Instant;

use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use transmutation::engines::security::SecurityEngine;
use transmutation::Result as TransResult;
use transmutation::agentic::{CodeMapEngine, structural_extraction};

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
    let log_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation"))
        .unwrap_or_else(|| PathBuf::from("."));
    std::fs::create_dir_all(&log_dir).ok();
    let file_appender = tracing_appender::rolling::daily(log_dir, "daemon.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);
    tracing_subscriber::fmt()
        .with_writer(non_blocking)
        .with_target(false)
        .init();

    tracing::info!("Starting Transmutation Daemon...");

    let security = match std::env::var("RULES_JSON_PATH") {
        Ok(path) => SecurityEngine::load_from_file(Path::new(&path)).unwrap(),
        Err(_) => {
            if let Ok(sec) = SecurityEngine::load_from_file(Path::new("rules.json")) {
                sec
            } else {
                SecurityEngine::load_from_str(include_str!("../../rules.json")).unwrap()
            }
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
    let start = Instant::now();
    let content = state.code_map.query_recon();
    let duration = start.elapsed().as_millis();

    let req_id = format!(
        "req_recon_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let record = AuditLogRecord {
        timestamp: chrono::Utc::now(),
        request_id: req_id.clone(),
        command: "query_recon".to_string(),
        exit_code: 0,
        security_ms: 0,
        shell_ms: 0,
        proxy_ms: duration,
        total_ms: duration,
        input_bytes: 0,
        output_bytes: content.len(),
    };
    let _ = offload_to_sqlite(&record, "", &content);

    Json(GenericResponse {
        content,
        is_error: false,
    })
}

async fn handle_impact(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<ImpactRequest>,
) -> Json<GenericResponse> {
    let start = Instant::now();
    let content = state.code_map.query_impact(&payload.symbol);
    let duration = start.elapsed().as_millis();

    let req_id = format!(
        "req_impact_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let record = AuditLogRecord {
        timestamp: chrono::Utc::now(),
        request_id: req_id.clone(),
        command: format!("query_impact {}", payload.symbol),
        exit_code: 0,
        security_ms: 0,
        shell_ms: 0,
        proxy_ms: duration,
        total_ms: duration,
        input_bytes: payload.symbol.len(),
        output_bytes: content.len(),
    };
    let _ = offload_to_sqlite(&record, &payload.symbol, &content);

    Json(GenericResponse {
        content,
        is_error: false,
    })
}

async fn handle_discovery(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CodeMapRequest>,
) -> Json<GenericResponse> {
    let start = Instant::now();
    // Merge Code Map with Latent-K Summary
    let map = state.code_map.read_code_map(&payload.filename);
    let raw_content = std::fs::read_to_string(&payload.filename).unwrap_or_default();
    let skeleton = structural_extraction(&raw_content);
    let final_content = format!("{map}\n\n[STRUCTURAL SKELETON (Latent-K)]\n{skeleton}");
    let duration = start.elapsed().as_millis();

    let req_id = format!(
        "req_discovery_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let record = AuditLogRecord {
        timestamp: chrono::Utc::now(),
        request_id: req_id.clone(),
        command: format!("query_discovery {}", payload.filename),
        exit_code: 0,
        security_ms: 0,
        shell_ms: 0,
        proxy_ms: duration,
        total_ms: duration,
        input_bytes: raw_content.len(),
        output_bytes: final_content.len(),
    };
    let _ = offload_to_sqlite(&record, &raw_content, &final_content);

    Json(GenericResponse {
        content: final_content,
        is_error: false,
    })
}

async fn handle_execute(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<ExecuteRequest>,
) -> Json<ExecuteResponse> {
    let start_rpc = Instant::now();
    let start_security = Instant::now();
    let platform = std::env::consts::OS;
    let security_result = state
        .security
        .evaluate(&payload.command, &payload.tool_name, platform);
    let security_ms = start_security.elapsed().as_millis();

    if let Some(error_msg) = security_result {
        return Json(ExecuteResponse {
            content: error_msg,
            is_error: true,
        });
    }

    match execute_secure_command(&payload.command, security_ms, start_rpc).await {
        Ok((output_text, is_error)) => Json(ExecuteResponse {
            content: output_text,
            is_error,
        }),
        Err(e) => Json(ExecuteResponse {
            content: format!("Proxy Error: {e}"),
            is_error: true,
        }),
    }
}

async fn handle_provenance(Json(payload): Json<ProvenanceRequest>) -> Json<GenericResponse> {
    match get_provenance_from_db(&payload.request_id) {
        Ok(audit_json) => Json(GenericResponse {
            content: audit_json,
            is_error: false,
        }),
        Err(e) => Json(GenericResponse {
            content: format!("Audit NotFound: {e}"),
            is_error: true,
        }),
    }
}

async fn execute_secure_command(
    cmd: &str,
    security_ms: u128,
    rpc_timer: Instant,
) -> Result<(String, bool), Box<dyn std::error::Error + Send + Sync>> {
    let start_shell = Instant::now();
    let req_id = format!(
        "req_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let temp_file = tempfile::Builder::new()
        .prefix("mcp_spool_")
        .suffix(".txt")
        .tempfile()?;

    let mut child = if cfg!(target_os = "windows") {
        tokio::process::Command::new("cmd")
            .arg("/c")
            .arg(cmd)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?
    } else {
        tokio::process::Command::new("sh")
            .arg("-c")
            .arg(cmd)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?
    };

    let mut stdout = child.stdout.take().unwrap();
    let mut stderr = child.stderr.take().unwrap();
    let mut file = tokio::fs::File::from_std(temp_file.reopen()?);
    tokio::io::copy(&mut stdout, &mut file).await?;
    tokio::io::copy(&mut stderr, &mut file).await?;
    let status = child.wait().await?;
    let shell_ms = start_shell.elapsed().as_millis();
    let raw_input = std::fs::read_to_string(temp_file.path()).unwrap_or_default();

    let record = AuditLogRecord {
        timestamp: chrono::Utc::now(),
        request_id: req_id,
        command: cmd.to_string(),
        exit_code: status.code().unwrap_or(-1),
        security_ms,
        shell_ms,
        proxy_ms: 0,
        total_ms: rpc_timer.elapsed().as_millis(),
        input_bytes: raw_input.len(),
        output_bytes: raw_input.len(),
    };
    if let Err(e) = offload_to_sqlite(&record, &raw_input, &raw_input) {
        tracing::error!("Failed to save audit log to SQLite: {e}");
    }
    Ok((raw_input, !status.success()))
}

fn get_provenance_from_db(
    req_id: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let db_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation"))
        .unwrap_or_else(|| PathBuf::from("."));
    let db_path = db_dir.join("audit.db");
    let conn = rusqlite::Connection::open(&db_path)?;
    let mut stmt = conn.prepare("SELECT e.*, c.raw_input, c.final_output FROM audit_events e JOIN audit_content c ON e.request_id = c.request_id WHERE e.request_id = ?")?;
    let mut rows = stmt.query_map([req_id], |row| {
        Ok(serde_json::json!({
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
        }))
    })?;
    if let Some(row) = rows.next() {
        Ok(serde_json::to_string_pretty(&row?)?)
    } else {
        Err("Request ID not found".into())
    }
}

fn offload_to_sqlite(
    record: &AuditLogRecord,
    raw_input: &str,
    final_output: &str,
) -> TransResult<()> {
    let db_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation"))
        .unwrap_or_else(|| PathBuf::from("."));
    let db_path = db_dir.join("audit.db");

    std::fs::create_dir_all(&db_dir).map_err(transmutation::TransmutationError::IoError)?;

    // Purge logic (1GB Budget)
    if let Ok(metadata) = std::fs::metadata(&db_path) {
        if metadata.len() > 1000 * 1024 * 1024 {
            if let Ok(conn) = rusqlite::Connection::open(&db_path) {
                // Delete oldest 500 records
                let _ = conn.execute("DELETE FROM audit_content WHERE request_id IN (SELECT request_id FROM audit_events ORDER BY timestamp ASC LIMIT 500)", []);
                let _ = conn.execute("DELETE FROM audit_events WHERE timestamp IN (SELECT timestamp FROM audit_events ORDER BY timestamp ASC LIMIT 500)", []);
                let _ = conn.execute("VACUUM", []);
            }
        }
    }

    let mut conn = rusqlite::Connection::open(&db_path).map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source(
            "SQLite",
            "Connection failed",
            e,
        )
    })?;
    let tx = conn.transaction().map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source("SQLite", "TX start failed", e)
    })?;
    tx.execute("CREATE TABLE IF NOT EXISTS audit_events (request_id TEXT PRIMARY KEY, timestamp TEXT, command TEXT, exit_code INTEGER, security_ms INTEGER, shell_ms INTEGER, proxy_ms INTEGER, total_ms INTEGER, input_bytes INTEGER, output_bytes INTEGER )", []).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Header table failed", e))?;
    tx.execute("CREATE TABLE IF NOT EXISTS audit_content (request_id TEXT PRIMARY KEY, raw_input TEXT, final_output TEXT, FOREIGN KEY(request_id) REFERENCES audit_events(request_id) )", []).map_err(|e| transmutation::TransmutationError::engine_error_with_source("SQLite", "Content table failed", e))?;
    tx.execute(
        "INSERT INTO audit_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rusqlite::params![
            record.request_id,
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
    )
    .map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source(
            "SQLite",
            "Header insert failed",
            e,
        )
    })?;
    tx.execute(
        "INSERT INTO audit_content VALUES (?, ?, ?)",
        rusqlite::params![record.request_id, raw_input, final_output,],
    )
    .map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source(
            "SQLite",
            "Content insert failed",
            e,
        )
    })?;
    tx.commit().map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source("SQLite", "TX commit failed", e)
    })?;
    Ok(())
}
