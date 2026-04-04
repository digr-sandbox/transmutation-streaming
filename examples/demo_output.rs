use std::collections::{HashMap, HashSet};
use std::fs;

use regex::Regex;

// --- TOON SQUEEZER (JSON/XML/HTML) ---
fn try_toon_compression(input: &str) -> Option<String> {
    if let Ok(val) = serde_json::from_str::<serde_json::Value>(input) {
        let mut out = String::new();
        flatten_toon(&val, &mut out, "");
        Some(out)
    } else if input.trim().starts_with('<') && input.trim().ends_with('>') {
        // Simulated XML/HTML minification (TOON-style flattening)
        let mut out = input.replace('\n', " ").replace("  ", " ");

        // 1. Remove closing tags entirely
        let closing_tag_re = Regex::new(r"</[^>]+>").unwrap();
        out = closing_tag_re.replace_all(&out, " ").to_string();

        // 2. Simplify opening tags to just their content (e.g. <dir name="x"/> -> dir name="x")
        let opening_tag_re = Regex::new(r"<([a-zA-Z0-9_-]+)([^>]*)>").unwrap();
        out = opening_tag_re.replace_all(&out, "$1$2 ").to_string();

        // 3. Remove quotes from attributes where possible to save tokens
        let attr_quotes_re = Regex::new(r#"="([^"]+)""#).unwrap();
        out = attr_quotes_re.replace_all(&out, "=$1").to_string();

        // Clean up excessive whitespace
        let whitespace_re = Regex::new(r"\s+").unwrap();
        out = whitespace_re.replace_all(&out, " ").to_string();

        Some(out.trim().to_string())
    } else {
        None
    }
}

fn flatten_toon(val: &serde_json::Value, out: &mut String, prefix: &str) {
    match val {
        serde_json::Value::Object(map) => {
            for (k, v) in map {
                let new_prefix = if prefix.is_empty() {
                    k.clone()
                } else {
                    format!("{}.{}", prefix, k)
                };
                if v.is_object() || v.is_array() {
                    flatten_toon(v, out, &new_prefix);
                } else {
                    out.push_str(&format!(
                        "{}:{} ",
                        new_prefix,
                        v.to_string().trim_matches('"')
                    ));
                }
            }
        }
        serde_json::Value::Array(arr) => {
            out.push_str(&format!("{}[{}]: ", prefix, arr.len()));
            for v in arr {
                if v.is_string() || v.is_number() || v.is_boolean() {
                    out.push_str(&format!("{} ", v.to_string().trim_matches('"')));
                }
            }
        }
        _ => {
            out.push_str(&format!(
                "{}:{} ",
                prefix,
                val.to_string().trim_matches('"')
            ));
        }
    }
}

// --- LATENT-K STRUCTURAL EXTRACTION ---
fn structural_extraction(original_input: &str) -> String {
    let mut lines = Vec::new();
    let mut in_block = false;
    let mut brace_depth = 0;

    for line in original_input.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("use ") || trimmed.starts_with("pub mod ") {
            lines.push(line.to_string());
            continue;
        }
        if trimmed.starts_with("pub struct ")
            || trimmed.starts_with("pub enum ")
            || trimmed.starts_with("pub fn ")
            || trimmed.starts_with("pub trait ")
            || trimmed.starts_with("impl ")
            || trimmed.starts_with("pub use ")
            || trimmed.starts_with("pub const ")
            || trimmed.starts_with("pub type ")
            || trimmed.starts_with("///")
        {
            if trimmed.ends_with("{") {
                in_block = true;
                brace_depth = 1;
                lines.push(format!("{} ... }}", line.trim_end_matches('{').trim_end()));
            } else {
                lines.push(line.to_string());
            }
            continue;
        }
        if in_block {
            if trimmed.contains("{") {
                brace_depth += 1;
            }
            if trimmed.contains("}") {
                brace_depth -= 1;
            }
            if brace_depth == 0 {
                in_block = false;
            }
            continue;
        }
        if trimmed.starts_with("#[") || trimmed.starts_with("#!") {
            lines.push(line.to_string());
        }
    }

    let mut result = "[DEPENDENCY MAP (k=1)]\n".to_string();
    let mut deps: Vec<&String> = lines
        .iter()
        .filter(|l| l.trim().starts_with("use "))
        .collect();
    if deps.is_empty() {
        result.push_str("(None detected)\n");
    }
    for d in deps {
        result.push_str(d);
        result.push('\n');
    }
    result.push_str("\n[PUBLIC INTERFACE]\n");
    for l in lines.iter().filter(|l| !l.trim().starts_with("use ")) {
        result.push_str(l);
        result.push('\n');
    }
    result.trim().to_string()
}

fn main() {
    println!("================================================================================");
    println!("🧪 DEMO: TOON SQUEEZER (JSON Output)");
    println!("================================================================================");
    let json_input = fs::read_to_string("tests/fixtures/payloads/project_structure.json").unwrap();
    if let Some(toon_output) = try_toon_compression(&json_input) {
        println!("Original Size: {} bytes", json_input.len());
        println!("TOON Size:     {} bytes\n", toon_output.len());
        println!("{}\n", toon_output);
    } else {
        println!("Failed to parse JSON for TOON compression.");
    }

    println!("================================================================================");
    println!("🧪 DEMO: TOON SQUEEZER (XML Output)");
    println!("================================================================================");
    let xml_input = fs::read_to_string("tests/fixtures/payloads/project_structure.xml").unwrap();
    if let Some(toon_xml_output) = try_toon_compression(&xml_input) {
        println!("Original Size: {} bytes", xml_input.len());
        println!("TOON Size:     {} bytes\n", toon_xml_output.len());
        println!("{}\n", toon_xml_output);
    } else {
        println!("Failed to parse XML for TOON compression.");
    }

    println!("================================================================================");
    println!("🧪 DEMO: LATENT-K STRUCTURAL EXTRACTION (Rust Code)");
    println!("================================================================================");
    let code_input = fs::read_to_string("tests/fixtures/payloads/cat_lib.txt").unwrap();
    let latent_k_output = structural_extraction(&code_input);
    println!("Original Size: {} bytes", code_input.len());
    println!("Latent-K Size: {} bytes\n", latent_k_output.len());
    println!("{}", latent_k_output);
}
