use std::io::{Write, BufRead, BufReader};
use std::process::{Command, Stdio};
use serde_json::json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🧪 MCP PROTOCOL COMPLIANCE TEST");
    println!("===============================");

    // 1. Spawn the MCP proxy binary
    let mut child = Command::new("cargo")
        .args(["run", "--release", "--quiet", "--features", "cli", "--bin", "transmutation-mcp-proxy"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;

    let mut stdin = child.stdin.take().ok_or("Failed to open stdin")?;
    let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
    let mut reader = BufReader::new(stdout);

    // TEST 1: Initialize Handshake
    println!("\n▶️  [INIT] Sending initialize...");
    let init_req = json!({
        "jsonrpc": "2.0",
        "id": "init_1",
        "method": "initialize",
        "params": {}
    });
    writeln!(stdin, "{}", init_req)?;
    
    let mut line = String::new();
    reader.read_line(&mut line)?;
    println!("   Response: {}", line.trim());
    assert!(line.contains("transmutation-secure-proxy"));
    assert!(line.contains("0.5.0"));

    // TEST 2: Tool Listing
    println!("\n▶️  [TOOLS] Sending tools/list...");
    let list_req = json!({
        "jsonrpc": "2.0",
        "id": "list_1",
        "method": "tools/list",
        "params": {}
    });
    writeln!(stdin, "{}", list_req)?;
    
    line.clear();
    reader.read_line(&mut line)?;
    println!("   Response: {}", line.trim());
    assert!(line.contains("execute_command"));
    assert!(line.contains("inputSchema"));

    // TEST 3: Liveness Ping (MCP 2026)
    println!("\n▶️  [PING] Sending ping...");
    let ping_req = json!({
        "jsonrpc": "2.0",
        "id": "ping_1",
        "method": "ping",
        "params": {}
    });
    writeln!(stdin, "{}", ping_req)?;
    
    line.clear();
    reader.read_line(&mut line)?;
    println!("   Response: {}", line.trim());
    assert!(line.contains("\"result\":{}"));

    // TEST 4: Protocol Error (Malformed JSON)
    println!("\n▶️  [ERROR] Sending malformed JSON...");
    writeln!(stdin, "{{{{{{ illegal_json }}}}")?; // Intentional malformed JSON
    
    // Note: The server might skip malformed lines or return an error depending on the loop.
    // Our current loop skips, but let's verify connectivity remains.
    
    // TEST 5: Valid Execution
    println!("\n▶️  [EXEC] Sending valid command...");
    let exec_req = json!({
        "jsonrpc": "2.0",
        "id": "exec_1",
        "method": "tools/call",
        "params": {
            "name": "execute_command",
            "arguments": { "command": "cmd /c echo protocol-verified" }
        }
    });
    writeln!(stdin, "{}", exec_req)?;
    
    line.clear();
    reader.read_line(&mut line)?;
    println!("   Response: {}", line.trim());
    assert!(line.contains("# ⚡ PROVENANCE"));
    assert!(line.contains("protocol-verified"));

    println!("\n✨ PROTOCOL SUCCESS: 2026 Model Context Protocol standards verified.");
    
    // Kill the child
    drop(stdin);
    let _ = child.wait();

    Ok(())
}
