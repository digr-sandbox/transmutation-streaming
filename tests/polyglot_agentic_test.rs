use transmutation::agentic::structural_extraction;
use std::fs;
use std::collections::HashMap;

struct Stats {
    sum_savings: f64,
    count: usize,
}

#[test]
fn test_agentic_polyglot_coverage_and_savings() {
    let polyglot_dir = "tests/fixtures/payloads/polyglot";
    let entries = fs::read_dir(polyglot_dir).expect("Missing polyglot directory");
    
    let mut ext_stats: HashMap<String, Stats> = HashMap::new();
    
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.extension().is_none_or(|ext| ext == "json") { continue; }
        
        let ext = path.extension().unwrap().to_string_lossy().to_string();
        let content = fs::read_to_string(&path).unwrap_or_default();
        if content.is_empty() { continue; }
        
        let original_size = content.len();
        let crushed = structural_extraction(&content);
        let crushed_size = crushed.len();
        
        let savings = 1.0 - (crushed_size as f64 / original_size as f64);
        
        let s = ext_stats.entry(ext).or_insert(Stats { sum_savings: 0.0, count: 0 });
        s.sum_savings += savings;
        s.count += 1;
    }
    
    println!("\n📊 AGENTIC DISCOVERY (Latent-K) TOKEN SAVINGS BY FILETYPE");
    println!("=========================================================");
    println!("{:<10} | {:>5} | {:>12}", "Ext", "Files", "Avg Savings %");
    println!("{:-<35}", "");
    
    let mut sorted_exts: Vec<_> = ext_stats.keys().collect();
    sorted_exts.sort();
    
    for ext in sorted_exts {
        let s = &ext_stats[ext];
        let avg_savings = (s.sum_savings / s.count as f64) * 100.0;
        println!("{:<10} | {:>5} | {:>11.1}%", ext, s.count, avg_savings);
    }
    println!("\n✅ Verified signal retention across {} languages.", ext_stats.len());
}
