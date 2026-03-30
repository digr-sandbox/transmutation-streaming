use transmutation::{ConversionOptions, Converter, OutputFormat};
use std::io::Write;
use tempfile::Builder;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input_text = r#"
# Introduction

This is a sample document passed as plain text.

## Features

1. Fast conversion
2. Pure Rust
3. LLM optimized

## Conclusion

It works perfectly!
"#;

    // Create a temporary file with a .txt extension
    let mut temp_file = Builder::new()
        .suffix(".txt")
        .tempfile()?;
        
    write!(temp_file, "{}", input_text)?;
    let path = temp_file.path();

    println!("Converting from temporary file: {}", path.display());

    // Initialize converter
    let converter = Converter::new()?;
    
    // Convert the text (from the temp file) to Markdown
    let result = converter
        .convert(path)
        .to(OutputFormat::Markdown { 
            split_pages: false, 
            optimize_for_llm: true 
        })
        .execute()
        .await?;
    
    // Output the result
    println!("\n--- CONVERTED OUTPUT ---");
    for chunk in result.content {
        println!("{}", String::from_utf8_lossy(&chunk.data));
    }
    
    Ok(())
}
