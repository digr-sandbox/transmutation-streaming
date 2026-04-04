pub trait DocumentConverter {
    fn convert(&self, path: &Path) -> Result<String, Error>;
}

pub struct PdfConverter {
    config: Config,
}

impl DocumentConverter for PdfConverter {
    fn convert(&self, path: &Path) -> Result<String, Error> {
        tracing::info!("Rust converting: {:?}", path);
        Ok("content".to_string())
    }
}