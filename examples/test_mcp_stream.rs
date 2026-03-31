use std::io::{Write, BufRead, BufReader};
use std::process::{Command, Stdio};
use serde_json::json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🧪 INTEGRATION TEST: Unified MCP Proxy Stream");
    println!("===========================================");

    // 1. Spawn the MCP proxy binary
    let mut child = Command::new("cargo")
        .args(["run", "--quiet", "--features", "cli", "--bin", "transmutation-mcp-proxy"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;

    let mut stdin = child.stdin.take().ok_or("Failed to open stdin")?;
    let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
    let mut reader = BufReader::new(stdout);

    // 2. Send INITIALIZE
    println!("\n▶️ Sending 'initialize'...");
    let init_req = json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {}
    });
    writeln!(stdin, "{}", init_req)?;
    
    let mut line = String::new();
    reader.read_line(&mut line)?;
    println!("  Result: {}", line.trim());
    assert!(line.contains("transmutation-secure-proxy"));

    // 2.5 Send PING (MCP 2026 Liveness Check)
    println!("\n▶️ Sending 'ping'...");
    let ping_req = json!({
        "jsonrpc": "2.0",
        "id": 1.5,
        "method": "ping",
        "params": {}
    });
    writeln!(stdin, "{}", ping_req)?;
    
    line.clear();
    reader.read_line(&mut line)?;
    println!("  Result: {}", line.trim());
    assert!(line.contains("\"result\":{}"));

    // 3. Send ALLOWED command (echo)
    println!("\n▶️ Sending ALLOWED command: 'cmd /c echo stream-integrity-check'...");
    let call_req = json!({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "execute_command",
            "arguments": { "command": "cmd /c echo stream-integrity-check" }
        }
    });
    writeln!(stdin, "{}", call_req)?;
    
    line.clear();
    reader.read_line(&mut line)?;
    println!("  Result: {}", line.trim());
    assert!(line.contains("# ⚡ PROVENANCE"));
    assert!(line.contains("stream-integrity-check"));
    assert!(line.contains("\"isError\":false"));

    // 4. Send BLOCKED command (cat .env)
    println!("\n▶️ Sending BLOCKED command: 'cat .env'...");
    let block_req = json!({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "execute_command",
            "arguments": { "command": "cat .env" }
        }
    });
    writeln!(stdin, "{}", block_req)?;
    
    line.clear();
    reader.read_line(&mut line)?;
    println!("  Result: {}", line.trim());
    assert!(line.contains("SECURITY BLOCKED"));
    assert!(line.contains("\"isError\":true"));

    println!("\n✨ INTEGRATION SUCCESS: All layers (Security -> Shell -> Transmute -> Audit) verified.");
    
    // Kill the child gracefully
    drop(stdin);
    let _ = child.wait();

    Ok(())
}
