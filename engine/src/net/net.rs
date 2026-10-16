use crate::engine::resolver::{EngineError, Result};
use serde::de::DeserializeOwned;
use serde_json::Value;
use std::fmt::Write;
use std::io::BufReader;
use std::time::Duration;
use ureq::http::{Method, Request, Response};
use ureq::{Agent, Body};

//limits
const MAX_BODY: u64 = 128 * 1024 * 1024;
const MAX_ERROR_BODY: u64 = 1024 * 1024;
const JSON_TIMEOUT: Duration = Duration::from_secs(300);
const RESPONSE_TIMEOUT: Duration = Duration::from_secs(30);
const METHODS: [&str; 5] = ["GET", "POST", "PUT", "PATCH", "DELETE"];

//client
#[derive(Clone)]
pub struct Http {
    agent: Agent,
    base: String,
}

//request helpers
pub fn encode_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*' | b'\'' | b'(' | b')' => {
                out.push(b as char)
            }
            _ => {
                let _ = write!(out, "%{b:02X}");
            }
        }
    }
    out
}

fn status_error(status: u16, body: &str) -> EngineError {
    if let Ok(Value::Object(map)) = serde_json::from_str::<Value>(body) {
        for key in ["error", "reason"] {
            match map.get(key) {
                None | Some(Value::Null) => {}
                Some(Value::String(s)) => return EngineError::new(s.clone()),
                Some(other) => return EngineError::new(other.to_string()),
            }
        }
    }
    EngineError::new(format!("http_{status}"))
}

fn ok_body(mut resp: Response<Body>) -> Result<Body> {
    let status = resp.status().as_u16();
    if (200..300).contains(&status) {
        return Ok(resp.into_body());
    }
    let text = resp
        .body_mut()
        .with_config()
        .limit(MAX_ERROR_BODY)
        .read_to_string()?;
    Err(status_error(status, &text))
}

//http methods
impl Http {
    pub fn new(base: &str) -> Self {
        let config = Agent::config_builder()
            .http_status_as_error(false)
            .timeout_connect(Some(Duration::from_secs(15)))
            .timeout_recv_response(Some(RESPONSE_TIMEOUT))
            .build();
        Self {
            agent: Agent::new_with_config(config),
            base: base.trim_end_matches('/').to_owned(),
        }
    }

    pub fn url(&self, path: &str) -> String {
        format!("{}{}", self.base, path)
    }

    pub fn agent(&self) -> &Agent {
        &self.agent
    }

    pub fn get_json<T: DeserializeOwned>(&self, url: &str) -> Result<T> {
        let resp = self
            .agent
            .get(url)
            .config()
            .timeout_global(Some(JSON_TIMEOUT))
            .build()
            .call()?;
        let reader = ok_body(resp)?.into_with_config().limit(MAX_BODY).reader();
        Ok(serde_json::from_reader(BufReader::new(reader))?)
    }

    pub fn get_value(&self, url: &str) -> Result<Value> {
        match self.get_json::<Value>(url)? {
            v @ Value::Object(_) => Ok(v),
            _ => Err(EngineError::new("invalid_response")),
        }
    }

    pub fn send(&self, method: &str, path: &str, token: Option<&str>, body: Option<&Value>) -> Result<Value> {
        let method = method.to_ascii_uppercase();
        if !METHODS.contains(&method.as_str()) {
            return Err(EngineError::new("unsupported_method"));
        }
        if !path.starts_with('/') || path.starts_with("//") || path.contains(['@', '\\']) {
            return Err(EngineError::new("invalid_path"));
        }
        let mut builder = Request::builder()
            .method(Method::from_bytes(method.as_bytes()).map_err(|_| EngineError::new("unsupported_method"))?)
            .uri(self.url(path));
        if let Some(t) = token {
            builder = builder.header("authorization", format!("Bearer {t}"));
        }
        let payload = match body {
            Some(v) => {
                builder = builder.header("content-type", "application/json; charset=utf-8");
                v.to_string()
            }
            None => String::new(),
        };
        let request = builder
            .body(payload)
            .map_err(|e| EngineError::new(format!("invalid_request_{e}")))?;
        let text = ok_body(self.agent.run(request)?)?
            .into_with_config()
            .limit(MAX_BODY)
            .read_to_string()?;
        match serde_json::from_str::<Value>(&text) {
            Ok(v @ Value::Object(_)) => Ok(v),
            _ if method != "GET" => Ok(Value::Object(Default::default())),
            _ => Err(EngineError::new("invalid_response")),
        }
    }

    pub fn download_url(&self, package_name: &str, version_code: i64) -> Result<String> {
        let url = self.url(&format!(
            "/store/apps/{}/download/{}",
            encode_component(package_name),
            version_code
        ));
        match self.get_value(&url)?.get("url").and_then(Value::as_str) {
            Some(s) if !s.is_empty() => Ok(s.to_owned()),
            _ => Err(EngineError::new("missing_url")),
        }
    }
}
