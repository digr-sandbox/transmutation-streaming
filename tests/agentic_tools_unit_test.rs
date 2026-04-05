use transmutation::agentic::{CodeMapEngine, structural_extraction};
use std::fs;

#[test]
fn test_unit_structural_extraction_and_token_savings() {
    let filename = "src/bin/transmutation.rs";
    let original_content = fs::read_to_string(filename).expect("Failed to read file");
    let original_size = original_content.len();

    let crushed = structural_extraction(&original_content);
    let crushed_size = crushed.len();

    // Accuracy: High-signal markers must be kept
    assert!(crushed.contains("fn main()"), "Signal lost: fn main()");
    assert!(crushed.contains("use "), "Signal lost: imports");
    assert!(crushed.contains("match "), "Signal lost: control flow");

    // Token Savings
    let savings = 1.0 - (crushed_size as f64 / original_size as f64);
    println!("File: {}, Original: {} bytes, Crushed: {} bytes, Savings: {:.1}%", 
        filename, original_size, crushed_size, savings * 100.0);

    assert!(savings > 0.20, "Compression ratio too low for Rust: {:.1}%", savings * 100.0);
}

#[test]
fn test_unit_code_map_recon() {
    let engine = CodeMapEngine::new();
    engine.build_initial_map();

    let recon = engine.query_recon();
    assert!(recon.contains("[ARCHITECTURAL RECONNAISSANCE]"));
    assert!(recon.contains("src: ["), "Recon failed to find src cluster");
    assert!(recon.contains("src/converters: ["), "Recon failed to find converters cluster");
}

#[test]
fn test_unit_code_map_impact() {
    let engine = CodeMapEngine::new();
    engine.build_initial_map();

    // Test impact of 'TransmutationError'
    let impact = engine.query_impact("TransmutationError");
    assert!(impact.contains("[BLAST RADIUS: TransmutationError]"));
    assert!(impact.contains("src/error.rs"), "Impact failed to find definition in error.rs");
    // Should find usages in main files
    assert!(impact.contains("src/lib.rs") || impact.contains("src/bin/transmutation.rs"), "Impact failed to find usages");
}

#[test]
fn test_unit_code_map_discovery_merge() {
    let engine = CodeMapEngine::new();
    engine.build_initial_map();

    let filename = "src/lib.rs";
    let map = engine.read_code_map(filename);
    
    assert!(map.contains("[ARCHITECTURE CODE MAP]"));
    assert!(map.contains(&format!("File: {filename}")));
    // lib.rs usually imports error.rs
    assert!(map.contains("src/error.rs") || map.contains("src/error/mod.rs"));
}
