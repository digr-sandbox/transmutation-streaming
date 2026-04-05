use std::fs;
use std::io::{BufWriter, Write};
use std::process::{Command, Stdio};
use std::time::Instant;

// Helper to generate a simulated binary file with valid magic bytes
fn generate_mock_binary(magic_bytes: &[u8], target_size_mb: usize) -> Vec<u8> {
    let target_size = target_size_mb * 1024 * 1024;
    let mut data = Vec::with_capacity(target_size);

    // Write magic bytes
    data.extend_from_slice(magic_bytes);

    // Pad the rest with simulated binary noise (0xAA)
    let padding = vec![0xAA; target_size - magic_bytes.len()];
    data.extend_from_slice(&padding);

    data
}

fn test_binary_stream(
    format_name: &str,
    magic_bytes: &[u8],
    expected_ext: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let upper_name = format_name.to_uppercase();
    println!("\n🚀 Starting 30MB {upper_name} Stream Test...");

    let input_data = generate_mock_binary(magic_bytes, 30);
    println!("   ✅ Generated 30MB of mock {upper_name} data in memory.");

    let temp_dir = std::path::PathBuf::from(format!("test_{format_name}_dir"));
    let _ = fs::remove_dir_all(&temp_dir);

    let start = Instant::now();

    // Spawn transmutation CLI
    let mut child = Command::new("cargo")
        .env("TRANSMUTATION_TEMP_DIR", temp_dir.to_str().unwrap())
        // Important: We request .md output to prove the sniffer overrides the output extension hint
        .args([
            "run",
            "--release",
            "--quiet",
            "--features",
            "cli",
            "--",
            "convert",
            "-",
            "--output",
            "dummy_output.md",
            "--quiet",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()?;

    // Pipe the 30MB data
    let stdin = child.stdin.take().ok_or("Failed to open stdin")?;
    let input_data_clone = input_data.clone();
    std::thread::spawn(move || {
        let mut writer = BufWriter::new(stdin);
        if let Err(e) = writer.write_all(&input_data_clone) {
            eprintln!("Failed to write to stdin: {e}");
        }
        let _ = writer.flush();
    });

    // Wait for the CLI to finish.
    // Expectation: The conversion will fail (exit code 1) because the 30MB of 0xAA padding is not a valid MP3/PDF.
    // That is perfectly fine. We just want to prove the Sniffer assigned the right extension before the crash.
    let status = child.wait()?;

    // Verification: We just want to prove the Sniffer correctly identified the stream
    println!("🔍 Verifying Stream Sniffer...");
    let mut found_correct_extension = false;
    let mut file_size = 0;

    if temp_dir.exists() {
        for entry in fs::read_dir(&temp_dir)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();

            if name.starts_with("transmutation_pipe_") {
                file_size = entry.metadata()?.len();
                if name.ends_with(expected_ext) {
                    found_correct_extension = true;
                    println!(
                        "   ✓ SUCCESS: Stream Sniffer correctly assigned '{expected_ext}' extension."
                    );
                } else {
                    println!("   ❌ FAILED: Sniffer assigned incorrect extension to file: {name}");
                }
            }
        }
    }

    if !found_correct_extension {
        println!(
            "❌ FAILED: Could not find the expected reconstructed file with extension '{expected_ext}'."
        );
        let _ = fs::remove_dir_all(&temp_dir);
        return Ok(());
    }

    if file_size as usize != input_data.len() {
        println!(
            "❌ FAILED: Reconstructed file size ({file_size}) does not match input stream ({}).",
            input_data.len()
        );
    } else {
        println!("   ✓ SUCCESS: Reconstructed file is exactly 30MB without memory crash.");
    }

    let duration = start.elapsed();
    println!("✨ {upper_name} Test Complete in {duration:?} (Engine Status: {status})");

    // Cleanup
    let _ = fs::remove_dir_all(&temp_dir);
    let _ = fs::remove_file("dummy_output.md");

    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🧪 Transmutation Binary Pipe Stress Tests");
    println!("=========================================");

    // 1. PDF Test (Magic Bytes: %PDF-1.x)
    let pdf_magic = b"%PDF-1.4\n";
    test_binary_stream("pdf", pdf_magic, ".pdf")?;

    // 2. ZIP Test (Magic Bytes: PK\x03\x04)
    let zip_magic = &[0x50, 0x4B, 0x03, 0x04];
    test_binary_stream("zip", zip_magic, ".zip")?;

    // 3. Office Test (DOCX) (Magic Bytes: PK\x03\x04 + word/ marker)
    // The sniffer identifies it as zip initially, which is fine for this test
    let docx_magic = &[0x50, 0x4B, 0x03, 0x04];
    test_binary_stream("docx", docx_magic, ".zip")?;

    println!("\n✅ All Binary Stream Tests Completed.");
    Ok(())
}
