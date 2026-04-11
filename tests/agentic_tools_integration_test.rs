use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use serde_json::{json, Value};
use reqwest::Client;

struct TestDaemon {
    child: Child,
}

impl TestDaemon {
    fn spawn() -> Self {
        let child = Command::new("cargo")
            .arg("run")
            .arg("--bin")
            .arg("daemon")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("Failed to spawn daemon");
        Self { child }
    }

    async fn wait_for_ready(&self) {
        let client = Client::new();
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(10) {
            if let Ok(res) = client.get("http://127.0.0.1:48192/health").send().await {
                if res.status().is_success() {
                    return;
                }
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        panic!("Daemon failed to become ready");
    }
}

impl Drop for TestDaemon {
    fn drop(&mut self) {
        let _ = self.child.kill();
    }
}

#[tokio::test]
async fn test_mcp_query_recon() {
    let daemon = TestDaemon::spawn();
    daemon.wait_for_ready().await;
    let client = Client::new();

    let res = client.post("http://127.0.0.1:48192/recon")
        .send()
        .await
        .expect("Failed to send recon request");

    assert!(res.status().is_success());
    let json: Value = res.json().await.expect("Failed to parse recon response");
    
    let content = json["content"].as_str().expect("Missing content");
    assert!(content.contains("[ARCHITECTURAL RECONNAISSANCE]"));
    // Verify it found some clusters
    assert!(content.contains("src: ["));
    assert!(content.contains("src/converters: ["));
}

#[tokio::test]
async fn test_mcp_query_impact() {
    let daemon = TestDaemon::spawn();
    daemon.wait_for_ready().await;
    let client = Client::new();

    // Test impact of 'TransmutationError'
    let res = client.post("http://127.0.0.1:48192/impact")
        .json(&json!({ "symbol": "TransmutationError" }))
        .send()
        .await
        .expect("Failed to send impact request");

    assert!(res.status().is_success());
    let json: Value = res.json().await.expect("Failed to parse impact response");
    
    let content = json["content"].as_str().expect("Missing content");
    assert!(content.contains("[BLAST RADIUS: TransmutationError]"));
    assert!(content.contains("src/error.rs"));
    // It should be used in many places
    assert!(content.contains("src/lib.rs") || content.contains("src/bin/transmutation.rs"));
}

#[tokio::test]
async fn test_mcp_query_discovery_and_token_savings() {
    let daemon = TestDaemon::spawn();
    daemon.wait_for_ready().await;
    let client = Client::new();

    let filename = "src/bin/transmutation.rs";
    let original_content = std::fs::read_to_string(filename).expect("Failed to read file");
    let original_size = original_content.len();

    let res = client.post("http://127.0.0.1:48192/discovery")
        .json(&json!({ "filename": filename }))
        .send()
        .await
        .expect("Failed to send discovery request");

    assert!(res.status().is_success());
    let json: Value = res.json().await.expect("Failed to parse discovery response");
    
    let crushed_content = json["content"].as_str().expect("Missing content");
    let crushed_size = crushed_content.len();

    // Accuracy Checks: Signal Retention
    assert!(crushed_content.contains("[ARCHITECTURE CODE MAP]"));
    assert!(crushed_content.contains("[STRUCTURAL SKELETON (Latent-K)]"));
    assert!(crushed_content.contains("fn main()"));
    assert!(crushed_content.contains("use "));
    
    // Token Savings (Compression) Check
    let savings = 1.0 - (crushed_size as f64 / original_size as f64);
    println!("File: {}, Original: {} bytes, Crushed: {} bytes, Savings: {:.1}%", 
        filename, original_size, crushed_size, savings * 100.0);

    // We expect at least 30% savings for a typical large Rust file like transmutation.rs
    assert!(savings > 0.30, "Compression ratio too low: {:.1}%", savings * 100.0);
}
