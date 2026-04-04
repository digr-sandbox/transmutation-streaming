use std::fs;

use regex::Regex;
use serde::Deserialize;

#[derive(Deserialize, Debug)]
pub struct RawRule {
    pub name: String,
    pub logic: String,
    pub message: String,
    pub platform: Option<String>,
}

#[derive(Debug)]
pub struct CompiledRule {
    pub name: String,
    pub logic: String,
    pub message: String,
    pub platform: Option<String>,
    pub pattern_map: Vec<(String, Regex)>,
}

#[derive(Debug)]
pub struct SecurityEngine {
    rules: Vec<CompiledRule>,
}

fn simple_eval_bool(expr: &str) -> bool {
    let mut s = expr.replace(" ", "");

    // Iteratively simplify
    loop {
        let old_s = s.clone();
        s = s.replace("!true", "false");
        s = s.replace("!false", "true");
        s = s.replace("(true)", "true");
        s = s.replace("(false)", "false");
        s = s.replace("true&&true", "true");
        s = s.replace("true&&false", "false");
        s = s.replace("false&&true", "false");
        s = s.replace("false&&false", "false");
        s = s.replace("true||true", "true");
        s = s.replace("true||false", "true");
        s = s.replace("false||true", "true");
        s = s.replace("false||false", "false");

        if s == old_s {
            break;
        }
    }

    s == "true"
}

impl SecurityEngine {
    pub fn load_from_str(
        json_content: &str,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let raw_rules: Vec<RawRule> = serde_json::from_str(json_content)?;
        let mut compiled_rules = Vec::new();

        for raw in raw_rules {
            let mut pattern_map = Vec::new();
            let mut last_end = 0;

            while let Some(start) = raw.logic[last_end..].find("matches('") {
                let absolute_start = last_end + start;
                let pattern_start = absolute_start + 9;
                if let Some(end_offset) = raw.logic[pattern_start..].find("')") {
                    let raw_pattern = &raw.logic[pattern_start..pattern_start + end_offset];
                    let compiled = Regex::new(raw_pattern)?;
                    pattern_map.push((raw_pattern.to_string(), compiled));
                    last_end = pattern_start + end_offset + 2;
                } else {
                    break;
                }
            }

            compiled_rules.push(CompiledRule {
                name: raw.name,
                logic: raw.logic,
                message: raw.message,
                platform: raw.platform,
                pattern_map,
            });
        }
        Ok(SecurityEngine {
            rules: compiled_rules,
        })
    }

    pub fn load_from_file(
        path: &std::path::Path,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let file_content = fs::read_to_string(path)?;
        Self::load_from_str(&file_content)
    }

    pub fn evaluate(&self, command: &str, tool_name: &str, platform: &str) -> Option<String> {
        for rule in &self.rules {
            // Filter by platform if specified
            if let Some(ref rule_platform) = rule.platform {
                if rule_platform.to_lowercase() != platform.to_lowercase() {
                    continue;
                }
            }

            let mut eval_logic = rule.logic.clone();

            // Replace tool name checks
            eval_logic = eval_logic.replace(
                "t.function.name == 'execute_secure_command'",
                &(tool_name == "execute_secure_command").to_string(),
            );
            eval_logic = eval_logic.replace(
                "t.function.name == 'delete_file'",
                &(tool_name == "delete_file").to_string(),
            );

            // Replace matches calls
            for (pattern_str, regex) in &rule.pattern_map {
                let call = format!("matches('{}')", pattern_str);
                eval_logic = eval_logic.replace(&call, &regex.is_match(command).to_string());
            }

            // Cleanup remaining parts
            eval_logic = eval_logic.replace("t.function.arguments.", "");
            eval_logic = eval_logic.replace("t.function.name", "false");

            if simple_eval_bool(&eval_logic) {
                return Some(format!(
                    "[SECURITY BLOCKED: {}] {}",
                    rule.name, rule.message
                ));
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get_test_engine() -> SecurityEngine {
        let rules_json = r#"[
            {
                "name": "01_Global_System_Vault",
                "logic": "t.function.arguments.matches('(?i).*(\\.bashrc|\\.zshrc|\\.pem|\\.key|credentials|shadow|passwd|id_).*')",
                "message": "Blocked."
            },
            {
                "name": "02_Config_DB_Isolation",
                "logic": "t.function.name == 'execute_secure_command' && t.function.arguments.matches('(?i).*(cat |grep |rg |ag |ack |less |more |vi |nano |view |edit |cp |mv |ln ).*(\\.env|config\\..*|\\.sqlite|\\.db).*')",
                "message": "Blocked."
            },
            {
                "name": "04_Timeout_Minimum_Enforcement",
                "logic": "t.function.name == 'execute_secure_command' && t.function.arguments.matches('(?i).*timeout\\s+([1-9]|[1-9][0-9]|[1-2][0-9][0-9])s?\\b.*')",  
                "message": "Blocked."
            }
        ]"#;
        SecurityEngine::load_from_str(rules_json).expect("Failed to parse test JSON")
    }

    #[test]
    fn test_safe_commands_pass() {
        let engine = get_test_engine();
        assert!(
            engine
                .evaluate("npm install", "execute_secure_command", "linux")
                .is_none()
        );
        assert!(
            engine
                .evaluate(
                    "timeout 300s npm run build",
                    "execute_secure_command",
                    "linux"
                )
                .is_none()
        );
    }

    #[test]
    fn test_platform_routing() {
        let rules_json = r#"[
            {
                "name": "WinRule",
                "platform": "windows",
                "logic": "t.function.arguments.matches('win-only')",
                "message": "Blocked."
            },
            {
                "name": "LinuxRule",
                "platform": "linux",
                "logic": "t.function.arguments.matches('linux-only')",
                "message": "Blocked."
            },
            {
                "name": "GlobalRule",
                "logic": "t.function.arguments.matches('global-block')",
                "message": "Blocked."
            }
        ]"#;
        let engine = SecurityEngine::load_from_str(rules_json).unwrap();

        // Windows context
        assert!(engine.evaluate("win-only", "exec", "windows").is_some());
        assert!(engine.evaluate("linux-only", "exec", "windows").is_none());
        assert!(engine.evaluate("global-block", "exec", "windows").is_some());

        // Linux context
        assert!(engine.evaluate("win-only", "exec", "linux").is_none());
        assert!(engine.evaluate("linux-only", "exec", "linux").is_some());
        assert!(engine.evaluate("global-block", "exec", "linux").is_some());
    }
}
