use std::io::{Write, BufRead, BufReader};
use std::process::{Command, Stdio};
use serde_json::json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🧪 SECURITY FIREWALL TEST: Thompson NFA Rejection");
    println!("===============================================");

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

    // 2. Test Cases: Malicious Intents
    let tests = vec![
        ("cat .env", "02_Config_DB_Isolation"),
        ("rm -rf /", "05_Bad_Regex_And_Redirection"),
        ("sudo ls", "07_Sudo_And_Blind_Execution"),
        ("timeout 10s npm install", "04_Timeout_Minimum_Enforcement"),
    ];

    for (cmd, expected_rule) in tests {
        println!("\n▶️  Sending malicious command: '{}'...", cmd);
        
        let req = json!({
            "jsonrpc": "2.0",
            "id": cmd,
            "method": "tools/call",
            "params": {
                "name": "execute_command",
                "arguments": { "command": cmd }
            }
        });
        writeln!(stdin, "{}", req)?;
        
        let mut line = String::new();
        reader.read_line(&mut line)?;
        let resp: serde_json::Value = serde_json::from_str(&line)?;
        
        let text = &resp["result"]["content"][0]["text"].as_str().unwrap();
        let is_error = resp["result"]["isError"].as_bool().unwrap();

        println!("  Result Status:  isError={}", is_error);
        println!("  Blocked Reason: {}", text);

        assert!(is_error, "Command '{}' was NOT rejected!", cmd);
        assert!(text.contains(expected_rule), "Rejection message did not contain rule '{}'", expected_rule);
        println!("  ✅ Successfully REJECTED by {}", expected_rule);
    }

    println!("\n✨ FIREWALL SUCCESS: All malicious intents were safely intercepted.");
    
    // Kill the child
    drop(stdin);
    let _ = child.wait();

    Ok(())
}
