use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};

use serde_json::json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🧪 EXHAUSTIVE SECURITY FIREWALL TEST (v12)");
    println!("===========================================");

    let mut child = Command::new("cargo")
        .args([
            "run",
            "--quiet",
            "--features",
            "cli",
            "--bin",
            "transmutation-mcp-proxy",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;

    let mut stdin = child.stdin.take().ok_or("Failed to open stdin")?;
    let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
    let mut reader = BufReader::new(stdout);

    let security_tests = vec![
        ("cat ~/.bashrc", "01_Global_System_Vault"),
        ("grep API_KEY .env", "02_Config_DB_Isolation"),
        ("env", "03_Secret_Hunting_Dumping"),
        ("timeout 10s sleep 1", "04_Timeout_Minimum_Enforcement"),
        ("rm -rf /", "05_Bad_Regex_And_Redirection"),
        ("gh repo delete", "06_GitHub_Contributor_Safety"),
        ("sudo ls", "07_Sudo_And_Blind_Execution"),
        ("terraform destroy", "09_Cloud_PaaS_Safety"),
    ];

    let mut passed = 0;

    for (cmd, rule) in &security_tests {
        println!("\n🛡️  Testing Rule: {} | Command: '{}'", rule, cmd);

        let req = json!({
            "jsonrpc": "2.0",
            "id": format!("test_{}", rule),
            "method": "tools/call",
            "params": {
                "name": "execute_secure_command",
                "arguments": { "command": cmd }
            }
        });
        writeln!(stdin, "{}", req)?;

        let mut line = String::new();
        reader.read_line(&mut line)?;
        let resp: serde_json::Value = serde_json::from_str(&line)?;

        let text = resp["result"]["content"][0]["text"].as_str().unwrap_or("");
        let is_error = resp["result"]["isError"].as_bool().unwrap_or(false);

        if is_error && text.contains(rule) {
            println!("   ✅ REJECTED correctly.");
            passed += 1;
        } else {
            println!("   ❌ FAILED to block or incorrect rule message.");
            println!("      Response: {}", text);
        }
    }

    println!("\n🛡️  Testing Allowed Command: 'cmd /c dir'...");
    let safe_req = json!({
        "jsonrpc": "2.0",
        "id": "safe_1",
        "method": "tools/call",
        "params": { "name": "execute_secure_command", "arguments": { "command": "cmd /c dir" } }
    });
    writeln!(stdin, "{}", safe_req)?;
    let mut line = String::new();
    reader.read_line(&mut line)?;
    if line.contains("\"isError\":false") {
        println!("   ✅ ALLOWED correctly.");
        passed += 1;
    }

    println!(
        "\n✨ SECURITY SUMMARY: {}/{} tests passed.",
        passed,
        security_tests.len() + 1
    );

    drop(stdin);
    let _ = child.wait();
    Ok(())
}
