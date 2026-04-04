use std::collections::HashMap;
use std::time::Instant;

/// --- PRUNING LAB: Feature Implementations ---

/// Feature 1: IDF Scoring (Inverse Document Frequency)
/// Measures how "unique" a word is in the entire 30MB document.
fn calculate_idf(words: &[String]) -> HashMap<String, f64> {
    let mut freq_map: HashMap<String, usize> = HashMap::new();
    for word in words {
        *freq_map.entry(word.clone()).or_insert(0) += 1;
    }

    let total = words.len() as f64;
    freq_map
        .into_iter()
        .map(|(word, count)| {
            // Formula: ln(Total Words / Word Count)
            let score = (total / count as f64).ln();
            (word, score)
        })
        .collect()
}

/// Feature 2: Local Entropy Analysis
/// Measures vocabulary diversity in a sliding window.
/// Detects repetitive "spam" logs vs "high-information" blocks.
fn calculate_entropy(words: &[String]) -> Vec<f64> {
    const WINDOW: usize = 10;
    (0..words.len())
        .map(|idx| {
            let start = idx.saturating_sub(WINDOW / 2);
            let end = (idx + WINDOW / 2).min(words.len());
            let window = &words[start..end];

            let unique_count = window
                .iter()
                .collect::<std::collections::HashSet<_>>()
                .len();
            // Ratio of unique words in the window
            unique_count as f64 / window.len() as f64
        })
        .collect()
}

/// Feature 3: POS Heuristics (Multilingual Stop-words)
/// Identifies "Function Words" that carry little meaning in shell logs.
fn calculate_pos_score(word: &str) -> f64 {
    const STOP_WORDS: &[&str] = &[
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "is", "was",
    ];
    if STOP_WORDS.contains(&word.to_lowercase().as_str()) {
        0.1 // Low importance
    } else if word.chars().any(|c| c.is_ascii_uppercase()) {
        1.0 // High importance (Identifiers/Constants)
    } else {
        0.5 // Neutral
    }
}

/// --- EVALUATION RUN ---

fn main() {
    println!("🧪 PROMPT PRUNING EVALUATION LAB");
    println!("================================");

    // 1. Generate 30MB of realistic log data
    println!("🚀 Generating 30MB log stream...");
    let log_templates = [
        "info: webpack compiled successfully",
        "error: connection reset by peer at 127.0.0.1",
        "debug: cache hit for key",
        "warning: deprecated api usage in src/lib.rs",
        "..........................................", // Low entropy spam
    ];

    let mut words = Vec::new();
    let mut current_bytes = 0;
    let target_bytes = 30 * 1024 * 1024;

    let mut i = 0;
    while current_bytes < target_bytes {
        let line = log_templates[i % log_templates.len()];
        for word in line.split_whitespace() {
            let w = word.to_string();
            current_bytes += w.len() + 1;
            words.push(w);
        }
        i += 1;
    }
    println!("✅ Generated {} tokens.", words.len());

    // 2. Run Feature Isolation Tests
    let start = Instant::now();

    println!("\n🔍 Running IDF Analysis (Global Uniqueness)...");
    let idf_map = calculate_idf(&words);

    println!("🔍 Running Entropy Analysis (Local Diversity)...");
    let entropy_scores = calculate_entropy(&words);

    let duration = start.elapsed();
    println!("✨ Analysis Complete in {:?}", duration);

    // 3. Display Findings
    println!("\n📊 [FEATURE 1: IDF] Top Results:");
    let mut idf_vec: Vec<_> = idf_map.iter().collect();
    idf_vec.sort_by(|a, b| b.1.partial_cmp(a.1).unwrap());

    println!("   Top 3 Unique (Signal):");
    for (w, s) in idf_vec.iter().take(3) {
        println!("     - {:<15} (Score: {:.2})", w, s);
    }

    println!("   Top 3 Common (Noise):");
    for (w, s) in idf_vec.iter().rev().take(3) {
        println!("     - {:<15} (Score: {:.2})", w, s);
    }

    println!("\n📊 [FEATURE 2: ENTROPY] Repetition Detection:");
    // Find a known low-entropy zone (the dots)
    let spam_idx = words.iter().position(|w| w.contains("...")).unwrap();
    println!(
        "   Low Entropy Zone (Spam):  {:.2}",
        entropy_scores[spam_idx]
    );
    // Find a high-entropy zone (the error)
    let signal_idx = words.iter().position(|w| w.contains("127.0.0.1")).unwrap();
    println!(
        "   High Entropy Zone (Signal): {:.2}",
        entropy_scores[signal_idx]
    );

    // 4. Combined Result Simulation
    println!("\n📊 [COMBINED] Pruning Simulation (50% Target):");
    let mut kept = 0;
    let mut total = 0;

    // Demonstrate pruning on a sample line
    let sample_line = "warning: the deprecated api is in src/lib.rs";
    print!("   Sample: \"{}\"\n   Result: \"", sample_line);
    for word in sample_line.split_whitespace() {
        let idf = idf_map.get(word).copied().unwrap_or(5.0);
        let pos = calculate_pos_score(word);
        let combined = (idf * 0.5) + (pos * 0.5);

        if combined > 3.0 {
            // Arbitrary threshold
            print!("{} ", word);
            kept += 1;
        }
        total += 1;
    }
    println!("\"");
    println!(
        "   Retention Rate: {:.1}%",
        (kept as f64 / total as f64) * 100.0
    );
}
