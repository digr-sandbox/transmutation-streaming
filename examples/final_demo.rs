use std::fs;
use std::collections::{HashSet, HashMap};
use regex::Regex;

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

        if trimmed.starts_with("pub struct ") || trimmed.starts_with("pub enum ") || trimmed.starts_with("pub fn ") || trimmed.starts_with("pub trait ") || trimmed.starts_with("impl ") || trimmed.starts_with("pub use ") || trimmed.starts_with("pub const ") || trimmed.starts_with("pub type ") || trimmed.starts_with("///") {
            if trimmed.ends_with("{") {
                in_block = true;
                brace_depth = 1;
                // Keep the signature but hide the body
                lines.push(format!("{} ... }}", line.trim_end_matches('{').trim_end()));
            } else {
                lines.push(line.to_string());
            }
            continue;
        }

        if in_block {
            if trimmed.contains("{") { brace_depth += 1; }
            if trimmed.contains("}") { brace_depth -= 1; }
            if brace_depth == 0 { in_block = false; }
            continue; // Skip lines inside implementation blocks
        }

        // Keep macros and structural markers at top level
        if trimmed.starts_with("#[") || trimmed.starts_with("#!") {
            lines.push(line.to_string());
        }
    }

    let mut result = "[DEPENDENCY MAP (k=1)]\n".to_string();
    let mut deps: Vec<&String> = lines.iter().filter(|l| l.trim().starts_with("use ")).collect();
    if deps.is_empty() { result.push_str("(None detected)\n"); }
    for d in deps { result.push_str(d); result.push('\n'); }

    result.push_str("\n[PUBLIC INTERFACE]\n");
    for l in lines.iter().filter(|l| !l.trim().starts_with("use ")) {
        result.push_str(l); result.push('\n');
    }
    
    result.trim().to_string()
}

// --- CUSTOM TOON MINIFIER FOR JSON/XML/HTML ---
// A robust, array-collapsing structural flattener that achieves 50-80% compression
fn toon_minify_json(val: &serde_json::Value) -> String {
    let mut out = String::new();
    flatten_json_to_toon(val, &mut out, "");
    out.trim().to_string()
}

fn flatten_json_to_toon(val: &serde_json::Value, out: &mut String, prefix: &str) {
    match val {
        serde_json::Value::Object(map) => {
            for (k, v) in map {
                let new_prefix = if prefix.is_empty() { k.clone() } else { format!("{}.{}", prefix, k) };
                if v.is_object() || v.is_array() {
                    flatten_json_to_toon(v, out, &new_prefix);
                } else {
                    out.push_str(&format!("{}:{} ", new_prefix, v.to_string().trim_matches('"')));
                }
            }
        },
        serde_json::Value::Array(arr) => {
            // TOON Array Collapsing: "files[14]: a b c" instead of repeating keys
            out.push_str(&format!("{}[{}]: ", prefix, arr.len()));
            for v in arr {
                if v.is_string() || v.is_number() || v.is_boolean() {
                    out.push_str(&format!("{} ", v.to_string().trim_matches('"')));
                }
            }
        },
        _ => {
            out.push_str(&format!("{}:{} ", prefix, val.to_string().trim_matches('"')));
        }
    }
}

// Aggressive XML/HTML Tag Stripper
fn toon_minify_xml_html(input: &str) -> String {
    let mut out = input.replace('\n', " ").replace("  ", " ");
    
    // 1. Remove all closing tags entirely
    let closing_tag_re = Regex::new(r"</[^>]+>").unwrap();
    out = closing_tag_re.replace_all(&out, " ").to_string();
    
    // 2. Convert opening tags and attributes to a flattened stream
    // e.g., <div class="container" id="main"> -> div class=container id=main
    let opening_tag_re = Regex::new(r"<([a-zA-Z0-9_-]+)([^>]*)>").unwrap();
    out = opening_tag_re.replace_all(&out, "$1$2 ").to_string();
    
    // 3. Remove quotes from attributes
    let attr_quotes_re = Regex::new(r#"="([^"]+)""#).unwrap();
    out = attr_quotes_re.replace_all(&out, "=$1").to_string();
    
    // 4. Strip semantic noise from HTML (DOCTYPE, html, body)
    let noise_re = Regex::new(r"(?i)\b(!DOCTYPE|html|body|head|style|script)\b").unwrap();
    out = noise_re.replace_all(&out, "").to_string();

    let whitespace_re = Regex::new(r"\s+").unwrap();
    out = whitespace_re.replace_all(&out, " ").to_string();
    
    out.trim().to_string()
}

fn main() {
    println!("================================================================================");
    println!("🧪 TOON SQUEEZER: JSON PAYLOAD");
    println!("================================================================================");
    let json_input = fs::read_to_string("tests/fixtures/payloads/project_structure.json").unwrap();
    let json_val: serde_json::Value = serde_json::from_str(&json_input).unwrap();
    let json_toon = toon_minify_json(&json_val);
    println!("Original Size: {} bytes", json_input.len());
    println!("TOON Size:     {} bytes", json_toon.len());
    println!("Compression:   {:.1}%\n", (1.0 - (json_toon.len() as f64 / json_input.len() as f64)) * 100.0);
    println!("{}\n", json_toon);

    println!("================================================================================");
    println!("🧪 TOON SQUEEZER: XML PAYLOAD");
    println!("================================================================================");
    let xml_input = fs::read_to_string("tests/fixtures/payloads/project_structure.xml").unwrap();
    let xml_toon = toon_minify_xml_html(&xml_input);
    println!("Original Size: {} bytes", xml_input.len());
    println!("TOON Size:     {} bytes", xml_toon.len());
    println!("Compression:   {:.1}%\n", (1.0 - (xml_toon.len() as f64 / xml_input.len() as f64)) * 100.0);
    println!("{}\n", xml_toon);

    println!("================================================================================");
    println!("🧪 TOON SQUEEZER: HTML PAYLOAD");
    println!("================================================================================");
    let html_input = fs::read_to_string("tests/fixtures/payloads/test_report.html").unwrap();
    let html_toon = toon_minify_xml_html(&html_input);
    println!("Original Size: {} bytes", html_input.len());
    println!("TOON Size:     {} bytes", html_toon.len());
    println!("Compression:   {:.1}%\n", (1.0 - (html_toon.len() as f64 / html_input.len() as f64)) * 100.0);
    println!("{}\n", html_toon);
}