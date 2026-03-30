use std::io::{Write, BufWriter};
use std::process::{Command, Stdio};
use std::time::Instant;
use std::fs;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let target_size = 30 * 1024 * 1024; // 30MB
    let mut current_size = 0;
    
    println!("🚀 Generating 30MB of simulated shell logs...");
    
    let log_templates = [
        "[npm] info it worked if it ends with ok",
        "[npm] info using npm@10.2.4",
        "[npm] info using node@v20.10.0",
        "[webpack] Compiling...",
        "[webpack] Compiled successfully in 1243ms",
        "[server] Server started on port 3000",
        "[db] Connected to database",
        "[auth] User login successful: user_123",
        "[api] GET /api/v1/users 200 45ms",
        "[api] POST /api/v1/orders 201 120ms",
        "[worker] Processing job_789...",
        "[worker] Job completed successfully",
        "[system] CPU Usage: 45%",
        "[system] Memory Usage: 1.2GB/16GB",
        "Error: Connection reset by peer (retrying in 5s...)",
        "Warning: Deprecated API usage in /src/utils/legacy.rs",
        "DEBUG: Cache hit for key 'user_data_456'",
        "INFO: Static assets served from /public",
        "[vite] hmr update /src/components/Header.tsx",
        "[jest] PASS tests/unit/auth.test.ts",
    ];

    // 1. Prepare the 30MB stream
    let mut input_data = Vec::with_capacity(target_size);
    let mut i = 0;
    while current_size < target_size {
        let line = format!("{}: {}\n", i, log_templates[i % log_templates.len()]);
        current_size += line.len();
        input_data.extend_from_slice(line.as_bytes());
        i += 1;
    }

    println!("✅ 30MB buffer ready ({} lines).", i);
    println!("🧪 Testing Batched Spooler (10MB chunks)...");

    let start = Instant::now();

    // 2. Spawn transmutation CLI with 'convert -'
    let temp_dir = std::path::PathBuf::from("test_chunks_dir");
    let _ = fs::remove_dir_all(&temp_dir); // Clean up before start
    
    let mut child = Command::new("cargo")
        .env("TRANSMUTATION_BATCH_SIZE", (10 * 1024 * 1024).to_string())
        .env("TRANSMUTATION_TEMP_DIR", temp_dir.to_str().unwrap())
        .args(["run", "--features", "cli", "--", "convert", "-", "--output", "heavy_output.txt", "--optimize-llm"])
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()?;

    // 3. Pipe the 30MB in a separate thread to avoid deadlocks
    let mut stdin = child.stdin.take().ok_or("Failed to open stdin")?;
    std::thread::spawn(move || {
        let mut writer = BufWriter::new(stdin);
        if let Err(e) = writer.write_all(&input_data) {
            eprintln!("Failed to write to stdin: {}", e);
        }
        let _ = writer.flush();
    });

    // 4. Wait for completion
    let status = child.wait()?;
    let duration = start.elapsed();

    if !status.success() {
        println!("\n❌ Test Failed: CLI returned status {}", status);
        return Ok(());
    }

    // 5. Verify Requirement 1: Single Reconstructed File was properly created
    println!("\n🔍 Verifying Requirement 1: Spooled file creation (No Chunks)...");
    let mut reconstructed_file_size = 0;
    let mut found_spool = false;
    if temp_dir.exists() {
        for entry in fs::read_dir(&temp_dir)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();
            // The new CLI logic uses prefix "transmutation_pipe_"
            if name.starts_with("transmutation_pipe_") {
                found_spool = true;
                reconstructed_file_size = entry.metadata()?.len();
                println!("   ✓ Found reconstructed file on disk: {} ({:.2} MB)", name, reconstructed_file_size as f64 / 1_000_000.0);
            }
        }
    }
    
    if !found_spool {
        println!("❌ Failed: Expected a single 'transmutation_pipe_*.txt' file in the temp directory, but none was found.");
        return Ok(());
    }
    
    // Verify it didn't drop a single byte during reconstruction from stdin
    if reconstructed_file_size as usize != target_size {
        println!("❌ Failed: Spooled file size ({}) does not exactly match input stream size ({}). Data was lost in the pipe!", reconstructed_file_size, target_size);
        return Ok(());
    } else {
        println!("   ✓ Spooled file size exactly matches the 30MB input stream!");
    }

    // 6. Verify Requirement 2: Final file is properly generated and Data Integrity
    println!("\n🔍 Verifying Requirement 2: Engine Processing and Data Integrity...");
    let final_output = std::path::Path::new("heavy_output.txt");
    if !final_output.is_file() {
        println!("❌ Failed: heavy_output.txt is not a file (it might be a directory or missing)");
        return Ok(());
    }
    
    let final_size = fs::metadata(final_output)?.len();
    println!("   ✓ Final engine output exists: heavy_output.txt ({:.2} MB)", final_size as f64 / 1_000_000.0);
    
    // Read the final file and verify line count and content
    use std::io::{BufRead, BufReader};
    let final_file = fs::File::open(final_output)?;
    let reader = BufReader::new(final_file);
    let mut final_line_count = 0;
    let mut last_line = String::new();
    
    for line in reader.lines() {
        if let Ok(l) = line {
            if !l.trim().is_empty() {
                last_line = l;
            }
            final_line_count += 1;
        }
    }

    
    println!("   ✓ Input generated {} lines.", i);
    println!("   ✓ Final file contains {} lines.", final_line_count);
    
    // The engine adds "# Document\n\n" headers, so final count will be slightly higher
    if final_line_count < i {
         println!("❌ Failed: Data loss detected! Final file has fewer lines than input.");
         return Ok(());
    }
    
    // Check if the last log entry is present to ensure truncation didn't happen
    let expected_last_prefix = format!("{}: ", i - 1);
    if last_line.starts_with(&expected_last_prefix) {
        println!("   ✓ Integrity Check Passed: Final line found successfully.");
    } else {
        println!("❌ Failed: Data loss detected! Last line missing or malformed.\nExpected prefix: '{}'\nFound: '{}'", expected_last_prefix, last_line);
        return Ok(());
    }
    
    // 7. Verify Requirement 3: The final file can be processed by the core engine
    println!("\n🔍 Verifying Requirement 3: Reprocessing the merged file...");
    let reprocess_status = Command::new("cargo")
        .args(["run", "--features", "cli", "--", "convert", "heavy_output.txt", "--output", "heavy_output_reprocessed.md"])
        .stdout(Stdio::null()) // Hide standard output for cleaner logs
        .status()?;
        
    if reprocess_status.success() {
        println!("   ✓ Core engine successfully parsed the merged file!");
    } else {
        println!("❌ Failed: Engine crashed or returned an error while parsing the merged file.");
        return Ok(());
    }

    println!("\n✨ All 3 Requirements Met! Test Successful in {:?}", duration);
    
    // Cleanup
    let _ = fs::remove_dir_all(&temp_dir);
    let _ = fs::remove_file("heavy_output.txt");
    let _ = fs::remove_file("heavy_output_reprocessed.md");

    Ok(())
}
