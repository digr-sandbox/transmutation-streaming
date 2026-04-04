use std::path::Path;

use tempfile::tempdir;
use transmutation::{Converter, OutputFormat};

#[cfg(feature = "office")]
fn create_real_docx(path: &Path) {
    use docx_rs::*;
    let file = std::fs::File::create(path).unwrap();
    Docx::new()
        .add_paragraph(Paragraph::new().add_run(Run::new().add_text("Hello Transmutation DOCX!")))
        .build()
        .pack(file)
        .unwrap();
}

#[cfg(feature = "office")]
fn create_real_xlsx(path: &Path) {
    use umya_spreadsheet::*;
    let mut book = Spreadsheet::default();
    let _ = book.new_sheet("Sheet1").unwrap();
    book.get_sheet_mut(&0)
        .unwrap()
        .get_cell_mut("A1")
        .set_value("Hello Transmutation XLSX!");
    writer::xlsx::write(&book, path).unwrap();
}

// For PPTX, I don't have a dedicated crate to create it easily,
// so I'll try to make the minimal ZIP better.
fn create_better_pptx(path: &Path) -> std::io::Result<()> {
    use std::fs::File;
    use std::io::Write;

    use zip::ZipWriter;
    use zip::write::FileOptions;

    let file = File::create(path)?;
    let mut zip = ZipWriter::new(file);
    let options: FileOptions<()> =
        FileOptions::default().compression_method(zip::CompressionMethod::Stored);

    // Marker file for detection
    zip.start_file("ppt/presentation.xml", options)?;
    zip.write_all(r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
    <p:sldIdLst><p:sldId id="256" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></p:sldIdLst>
</p:presentation>"#.as_bytes())?;

    zip.start_file("ppt/slides/slide1.xml", options)?;
    zip.write_all(r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
    <p:cSld>
        <p:spTree>
            <p:sp>
                <p:txBody>
                    <a:p><a:r><a:t>Hello Transmutation PPTX!</a:t></a:r></a:p>
                </p:txBody>
            </p:sp>
        </p:spTree>
    </p:cSld>
</p:sld>"#.as_bytes())?;

    zip.finish()?;
    Ok(())
}

#[tokio::test]
#[cfg(feature = "office")]
async fn test_docx_conversion() {
    let dir = tempdir().unwrap();
    let file_path = dir.path().join("test.docx");
    create_real_docx(&file_path);

    let converter = Converter::new().unwrap();
    let result = converter
        .convert(&file_path)
        .to(OutputFormat::Markdown {
            split_pages: false,
            optimize_for_llm: true,
        })
        .execute()
        .await
        .unwrap();

    let output_text = String::from_utf8_lossy(&result.content[0].data);
    assert!(output_text.contains("Hello Transmutation DOCX!"));

    println!(
        "DOCX Compaction: {} bytes -> {} bytes",
        result.statistics.input_size_bytes, result.statistics.output_size_bytes
    );
}

#[tokio::test]
async fn test_pptx_conversion() {
    let dir = tempdir().unwrap();
    let file_path = dir.path().join("test.pptx");
    create_better_pptx(&file_path).unwrap();

    let converter = Converter::new().unwrap();
    let result = converter
        .convert(&file_path)
        .to(OutputFormat::Markdown {
            split_pages: false,
            optimize_for_llm: true,
        })
        .execute()
        .await
        .unwrap();

    let output_text = String::from_utf8_lossy(&result.content[0].data);
    assert!(output_text.contains("Hello Transmutation PPTX!"));

    println!(
        "PPTX Compaction: {} bytes -> {} bytes",
        result.statistics.input_size_bytes, result.statistics.output_size_bytes
    );
}

#[tokio::test]
#[cfg(feature = "office")]
async fn test_xlsx_conversion() {
    let dir = tempdir().unwrap();
    let file_path = dir.path().join("test.xlsx");
    create_real_xlsx(&file_path);

    let converter = Converter::new().unwrap();
    let result = converter
        .convert(&file_path)
        .to(OutputFormat::Markdown {
            split_pages: false,
            optimize_for_llm: true,
        })
        .execute()
        .await
        .unwrap();

    let output_text = String::from_utf8_lossy(&result.content[0].data);
    assert!(output_text.contains("Hello Transmutation XLSX!"));

    println!(
        "XLSX Compaction: {} bytes -> {} bytes",
        result.statistics.input_size_bytes, result.statistics.output_size_bytes
    );
}
