//! Transmutation CLI - Command Line Interface for document conversion
//!
//! This binary provides a command-line interface to the Transmutation library,
//! allowing users to convert documents from the terminal on Windows, Mac, and Linux.

#![allow(
    unused_imports,
    unexpected_cfgs,
    clippy::uninlined_format_args,
    clippy::vec_init_then_push
)]

use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Instant;

use clap::{Parser, Subcommand, ValueEnum};
use colored::*;
use transmutation::{ConversionOptions, Converter, ImageQuality, OutputFormat, Result};

#[derive(Parser)]
#[command(
    name = "transmutation",
    version,
    about = "High-performance document conversion engine for AI/LLM embeddings",
    long_about = "Transmutation converts documents to LLM-optimized formats (Markdown, Images, JSON)\n\
                  Supporting 20+ formats including PDF, DOCX, PPTX, XLSX, images, audio, and video."
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Enable verbose output
    #[arg(short, long, global = true)]
    verbose: bool,

    /// Quiet mode (minimal output)
    #[arg(short, long, global = true)]
    quiet: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Convert a document to another format
    Convert {
        /// Input file path
        #[arg(value_name = "INPUT")]
        input: PathBuf,

        /// Output file path
        #[arg(short, long, value_name = "OUTPUT")]
        output: Option<PathBuf>,

        /// Output directory for split pages/images (used with --split-pages or image formats)
        #[arg(short = 'd', long, value_name = "DIR")]
        output_dir: Option<PathBuf>,

        /// Output format
        #[arg(short = 'f', long, value_enum, default_value = "markdown")]
        format: OutputFormatArg,

        /// Split output by pages
        #[arg(short = 's', long)]
        split_pages: bool,

        /// Optimize for LLM processing
        #[arg(short = 'l', long)]
        optimize_llm: bool,

        /// Use high-precision mode (Docling-based, slower but ~95% accurate vs ~81% fast mode)
        #[arg(short = 'P', long)]
        precision: bool,

        /// Use docling-parse C++ FFI for maximum precision (95%+ similarity)
        /// Requires compilation with --features docling-ffi
        #[arg(long)]
        ffi: bool,

        /// Image quality (1-100)
        #[arg(short = 'Q', long, default_value = "85")]
        quality: u8,

        /// DPI for image output
        #[arg(long, default_value = "150")]
        dpi: u32,
    },

    /// Batch convert multiple documents
    Batch {
        /// Input directory or glob pattern
        #[arg(value_name = "INPUT")]
        input: String,

        /// Output directory
        #[arg(short, long, value_name = "OUTPUT")]
        output: PathBuf,

        /// Output format
        #[arg(short = 'f', long, value_enum, default_value = "markdown")]
        format: OutputFormatArg,

        /// Number of parallel workers
        #[arg(short = 'j', long, default_value = "4")]
        jobs: usize,

        /// Continue on errors
        #[arg(short = 'c', long)]
        continue_on_error: bool,
    },

    /// Show information about a document
    Info {
        /// Input file path
        #[arg(value_name = "INPUT")]
        input: PathBuf,
    },

    /// List supported formats
    Formats,

    /// Run a command and capture/optimize its output
    Run {
        /// Command to run (e.g. -- npm test)
        #[arg(last = true, required = true)]
        command: Vec<String>,

        /// Output file path
        #[arg(short, long, value_name = "OUTPUT")]
        output: Option<PathBuf>,

        /// Output format
        #[arg(short = 'f', long, value_enum, default_value = "markdown")]
        format: OutputFormatArg,

        /// Optimize for LLM processing
        #[arg(short = 'l', long)]
        optimize_llm: bool,
    },

    /// Show version and build information
    Version,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum OutputFormatArg {
    /// Markdown format
    Markdown,
    /// PNG image
    Png,
    /// JPEG image
    Jpeg,
    /// WebP image
    Webp,
    /// JSON format
    Json,
    /// CSV format (for spreadsheets)
    Csv,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    // Initialize logging
    let log_level = if cli.verbose {
        tracing::Level::DEBUG
    } else if cli.quiet {
        tracing::Level::ERROR
    } else {
        tracing::Level::INFO
    };

    tracing_subscriber::fmt()
        .with_max_level(log_level)
        .with_target(false)
        .init();

    // Run command
    if let Err(e) = run_command(cli).await {
        eprintln!("{} {}", "Error:".red().bold(), e);
        std::process::exit(1);
    }
}

async fn run_command(cli: Cli) -> Result<()> {
    match cli.command {
        Commands::Convert {
            input,
            output,
            output_dir,
            format,
            split_pages,
            optimize_llm,
            precision,
            ffi,
            quality,
            dpi,
        } => {
            if !cli.quiet {
                println!("{}", "Converting document...".cyan().bold());
            }

            // Determine output format
            let output_format = match format {
                OutputFormatArg::Markdown => OutputFormat::Markdown {
                    split_pages,
                    optimize_for_llm: optimize_llm,
                },
                OutputFormatArg::Json => OutputFormat::Json {
                    structured: true,
                    include_metadata: true,
                },
                OutputFormatArg::Png => OutputFormat::Image {
                    format: transmutation::ImageFormat::Png,
                    quality,
                    dpi,
                },
                OutputFormatArg::Jpeg => OutputFormat::Image {
                    format: transmutation::ImageFormat::Jpeg,
                    quality,
                    dpi,
                },
                OutputFormatArg::Webp => OutputFormat::Image {
                    format: transmutation::ImageFormat::Webp,
                    quality,
                    dpi,
                },
                OutputFormatArg::Csv => OutputFormat::Csv {
                    delimiter: ',',
                    include_headers: true,
                },
            };

            let output_path = output.unwrap_or_else(|| {
                if input.to_str() == Some("-") {
                    PathBuf::from(match format {
                        OutputFormatArg::Markdown => "output.md",
                        OutputFormatArg::Png => "output.png",
                        OutputFormatArg::Jpeg => "output.jpg",
                        OutputFormatArg::Webp => "output.webp",
                        OutputFormatArg::Json => "output.json",
                        OutputFormatArg::Csv => "output.csv",
                    })
                } else {
                    let mut path = input.clone();
                    path.set_extension(match format {
                        OutputFormatArg::Markdown => "md",
                        OutputFormatArg::Png => "png",
                        OutputFormatArg::Jpeg => "jpg",
                        OutputFormatArg::Webp => "webp",
                        OutputFormatArg::Json => "json",
                        OutputFormatArg::Csv => "csv",
                    });
                    path
                }
            });

            if !cli.quiet {
                println!("  Output: {}", output_path.display());
                println!("  Format: {:?}", format);
            }

            // Create converter
            let converter = Converter::new()?;

            // Configure options
            let options = ConversionOptions {
                split_pages,
                optimize_for_llm: optimize_llm,
                use_precision_mode: precision,
                use_ffi: ffi,
                extract_tables: true,
                image_quality: ImageQuality::High,
                dpi,
                ..Default::default()
            };

            // Show mode information
            if !cli.quiet && ffi {
                println!(
                    "{}",
                    "  Mode:   FFI (docling-parse C++, 95%+ similarity target)"
                        .green()
                        .bold()
                );
            } else if !cli.quiet && precision {
                println!(
                    "{}",
                    "  Mode:   Precision (Enhanced heuristics, 82%+ similarity)".yellow()
                );
            } else if !cli.quiet {
                println!(
                    "{}",
                    "  Mode:   Fast (Pure Rust, 71.8% similarity, 250x faster)".green()
                );
            }

            // Perform conversion
            let start = Instant::now();

            let mut _temp_file_guard = None;
            let actual_input = if input.to_str() == Some("-") {
                if !cli.quiet {
                    println!("  Input:  (stdin spooled to single file)");
                }

                use std::io::{self, Read};
                let mut stdin = io::stdin().lock();

                // Allow overriding temp dir for testing
                let custom_temp = std::env::var("TRANSMUTATION_TEMP_DIR")
                    .ok()
                    .map(PathBuf::from);
                if let Some(ref d) = custom_temp {
                    std::fs::create_dir_all(d)
                        .map_err(transmutation::TransmutationError::IoError)?;
                }

                // 1. Sniff the first 8KB to determine the true file format
                let mut sniff_buffer = vec![0; 8192];
                let mut sniff_len = 0;
                while sniff_len < 8192 {
                    let n = stdin
                        .read(&mut sniff_buffer[sniff_len..])
                        .map_err(transmutation::TransmutationError::IoError)?;
                    if n == 0 {
                        break;
                    }
                    sniff_len += n;
                }
                sniff_buffer.truncate(sniff_len);

                // Detect format using file-format crate natively
                let format_detector = file_format::FileFormat::from_bytes(&sniff_buffer);
                let detected_ext = format_detector.extension();

                // The temp file represents the INPUT, so it must use the detected input extension.
                let final_ext = if detected_ext == "id3" {
                    "mp3"
                } else if detected_ext != "bin" && !detected_ext.is_empty() {
                    detected_ext
                } else {
                    "txt"
                };

                let mut builder = tempfile::Builder::new();
                builder.prefix("transmutation_pipe_");
                let ext_string = format!(".{}", final_ext);
                builder.suffix(&ext_string);

                let mut temp_file = match custom_temp {
                    Some(ref d) => builder
                        .tempfile_in(d)
                        .map_err(transmutation::TransmutationError::IoError)?,
                    None => builder
                        .tempfile()
                        .map_err(transmutation::TransmutationError::IoError)?,
                };

                if !cli.quiet {
                    println!(
                        "  Detected Stream Format: .{} (via {})",
                        final_ext,
                        format_detector.media_type()
                    );
                    println!("  Streaming stdin to disk... (Constant RAM usage)");
                }

                // Write the sniffed bytes first
                temp_file
                    .write_all(&sniff_buffer)
                    .map_err(transmutation::TransmutationError::IoError)?;

                // Spool the rest of the stream into the single temp file
                std::io::copy(&mut stdin, &mut temp_file)
                    .map_err(transmutation::TransmutationError::IoError)?;
                temp_file
                    .flush()
                    .map_err(transmutation::TransmutationError::IoError)?;

                let path = temp_file.path().to_path_buf();

                if custom_temp.is_some() {
                    // Leak the temp file for testing purposes so the test script can inspect it
                    let (_, path) = temp_file.keep().unwrap();
                    path
                } else {
                    // Keep the guard so it deletes at the end of scope
                    _temp_file_guard = Some(temp_file);
                    path
                }
            } else {
                if !cli.quiet {
                    println!("  Input:  {}", input.display());
                }
                input.clone()
            };

            let result = converter
                .convert(&actual_input)
                .to(output_format)
                .with_options(options)
                .execute()
                .await?;

            let duration = start.elapsed();

            // Save output(s)
            if result.content.len() > 1 {
                let stem = output_path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("output");
                let parent = if let Some(ref dir) = output_dir {
                    tokio::fs::create_dir_all(dir).await?;
                    dir.clone()
                } else {
                    output_path
                        .parent()
                        .map(|p| p.to_path_buf())
                        .unwrap_or_else(|| PathBuf::from("."))
                };
                let ext = output_path
                    .extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("md");

                for chunk in &result.content {
                    let page_path = parent.join(format!("{}_{}.{}", stem, chunk.page_number, ext));
                    tokio::fs::write(&page_path, &chunk.data).await?;
                }
            } else {
                result.save(&output_path).await?;
            }

            // Display statistics
            if !cli.quiet {
                println!();
                println!("{}", "Statistics:".yellow().bold());
                println!("  Duration:     {:?}", duration);
                println!("  Pages:        {}", result.statistics.pages_processed);
                println!(
                    "  Input size:   {:.2} MB",
                    result.statistics.input_size_bytes as f64 / 1_000_000.0
                );
                println!(
                    "  Output size:  {:.2} MB",
                    result.statistics.output_size_bytes as f64 / 1_000_000.0
                );
            }

            Ok(())
        }

        Commands::Run {
            command,
            output: _,
            format,
            optimize_llm,
        } => {
            if !cli.quiet {
                println!("{}", "🚀 Proxy Runner starting...".cyan().bold());
                println!("  Command: {}", command.join(" "));
            }

            let start_shell = Instant::now();

            // 1. Spool child output to a temporary file
            let mut builder = tempfile::Builder::new();
            builder.prefix("transmutation_run_");
            builder.suffix(".txt");
            let mut temp_file = builder
                .tempfile()
                .map_err(transmutation::TransmutationError::IoError)?;

            // 2. Spawn and capture (Merged stdout/stderr)
            let mut child = std::process::Command::new(&command[0])
                .args(&command[1..])
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
                .map_err(transmutation::TransmutationError::IoError)?;

            let mut stdout = child.stdout.take().unwrap();
            let mut stderr = child.stderr.take().unwrap();

            // Stream both to the same file
            std::io::copy(&mut stdout, &mut temp_file)
                .map_err(transmutation::TransmutationError::IoError)?;
            std::io::copy(&mut stderr, &mut temp_file)
                .map_err(transmutation::TransmutationError::IoError)?;

            let status = child
                .wait()
                .map_err(transmutation::TransmutationError::IoError)?;
            let shell_duration = start_shell.elapsed();

            if !cli.quiet {
                println!("  Status:  {}", status);
                println!("  Shell Time: {:?}", shell_duration);
            }

            // 3. Convert/Prune spooled output
            let start_proxy = Instant::now();
            let converter = Converter::new()?;

            let output_format = match format {
                OutputFormatArg::Markdown => OutputFormat::Markdown {
                    split_pages: false,
                    optimize_for_llm: optimize_llm,
                },
                OutputFormatArg::Json => OutputFormat::Json {
                    structured: true,
                    include_metadata: true,
                },
                OutputFormatArg::Png => OutputFormat::Image {
                    format: transmutation::ImageFormat::Png,
                    quality: 85,
                    dpi: 150,
                },
                OutputFormatArg::Jpeg => OutputFormat::Image {
                    format: transmutation::ImageFormat::Jpeg,
                    quality: 85,
                    dpi: 150,
                },
                OutputFormatArg::Webp => OutputFormat::Image {
                    format: transmutation::ImageFormat::Webp,
                    quality: 85,
                    dpi: 150,
                },
                OutputFormatArg::Csv => OutputFormat::Csv {
                    delimiter: ',',
                    include_headers: true,
                },
            };

            let result = converter
                .convert(temp_file.path())
                .to(output_format)
                .execute()
                .await?;

            let proxy_duration = start_proxy.elapsed();

            // 4. Persistence & Audit
            let record = AuditLogRecord {
                timestamp: chrono::Utc::now(),
                command: command.join(" "),
                exit_code: status.code().unwrap_or(-1),
                shell_ms: shell_duration.as_millis(),
                proxy_ms: proxy_duration.as_millis(),
                input_bytes: result.statistics.input_size_bytes as usize,
                output_bytes: result.statistics.output_size_bytes as usize,
            };

            if let Err(e) = offload_to_sqlite(&record) {
                eprintln!("{} Audit logging failed: {}", "WARN:".yellow(), e);
            }

            // 5. Output to user
            for chunk in result.content {
                std::io::stdout().write_all(&chunk.data).unwrap();
            }

            Ok(())
        }

        Commands::Batch { .. } => Ok(()), // Placeholder
        Commands::Info { .. } => Ok(()),  // Placeholder
        Commands::Formats => Ok(()),      // Placeholder
        Commands::Version => {
            println!("Transmutation CLI v{}", transmutation::VERSION);
            Ok(())
        }
    }
}

struct AuditLogRecord {
    timestamp: chrono::DateTime<chrono::Utc>,
    command: String,
    exit_code: i32,
    shell_ms: u128,
    proxy_ms: u128,
    input_bytes: usize,
    output_bytes: usize,
}

fn offload_to_sqlite(record: &AuditLogRecord) -> Result<()> {
    let db_dir = dirs::home_dir()
        .map(|p| p.join(".transmutation"))
        .unwrap_or_else(|| PathBuf::from("."));

    std::fs::create_dir_all(&db_dir).map_err(transmutation::TransmutationError::IoError)?;
    let db_path = db_dir.join("audit.db");

    // Purge logic (1GB Budget)
    if let Ok(metadata) = std::fs::metadata(&db_path) {
        if metadata.len() > 1000 * 1024 * 1024 {
            let conn = rusqlite::Connection::open(&db_path).map_err(|e| {
                transmutation::TransmutationError::engine_error_with_source(
                    "SQLite",
                    "Connection failed",
                    e,
                )
            })?;
            let _ = conn.execute("DELETE FROM audit_events WHERE timestamp IN (SELECT timestamp FROM audit_events ORDER BY timestamp ASC LIMIT 500)", []);
            let _ = conn.execute("VACUUM", []);
        }
    }

    let conn = rusqlite::Connection::open(&db_path).map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source(
            "SQLite",
            "Connection failed",
            e,
        )
    })?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS audit_events (
            timestamp TEXT,
            command TEXT,
            exit_code INTEGER,
            shell_ms INTEGER,
            proxy_ms INTEGER,
            input_bytes INTEGER,
            output_bytes INTEGER
        )",
        [],
    )
    .map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source(
            "SQLite",
            "Table creation failed",
            e,
        )
    })?;

    conn.execute(
        "INSERT INTO audit_events VALUES (?, ?, ?, ?, ?, ?, ?)",
        rusqlite::params![
            record.timestamp.to_rfc3339(),
            record.command,
            record.exit_code,
            record.shell_ms as i64,
            record.proxy_ms as i64,
            record.input_bytes as i64,
            record.output_bytes as i64,
        ],
    )
    .map_err(|e| {
        transmutation::TransmutationError::engine_error_with_source("SQLite", "Insert failed", e)
    })?;

    Ok(())
}
