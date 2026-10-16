use crate::data::catalog::Catalog;
use crate::data::data::{App, Index};
use crate::engine::resolver::{EngineError, Result};
use crate::net::net::Http;
use serde_json::Value;

//sync outcome
pub enum Outcome {
    Full(Index),
    Patch {
        timestamp: i64,
        updates: Vec<App>,
        removes: Vec<String>,
    },
    Unchanged,
}

fn invalid_state() -> EngineError {
    EngineError::new("sync_invalid_state")
}

//sync entry
pub fn sync_store(http: &Http, baseline: Option<&Catalog>) -> Result<Outcome> {
    let since = baseline.map_or(0, |b| b.timestamp);
    let mut body = http.get_value(&http.url(&format!("/store/sync?since={since}")))?;
    let action = body.get("action").and_then(Value::as_str).map(str::to_owned);
    match (action.as_deref(), baseline) {
        (Some("full"), _) => full(http, baseline),
        (Some("patch"), Some(base)) => patch(http, base, &mut body),
        _ => Err(invalid_state()),
    }
}

//full index
fn full(http: &Http, baseline: Option<&Catalog>) -> Result<Outcome> {
    let index: Index = http.get_json(&http.url("/store/index.json"))?;
    if index.apps.is_empty() {
        return Err(EngineError::new("empty_index"));
    }
    if index.timestamp <= 0 {
        return Err(EngineError::new("invalid_timestamp"));
    }
    if baseline.is_some_and(|b| index.apps.len() * 2 < b.apps.len()) {
        return Err(EngineError::new("index_shrunk"));
    }
    Ok(Outcome::Full(index))
}

//patches
fn patch(http: &Http, base: &Catalog, body: &mut Value) -> Result<Outcome> {
    let timestamp = body
        .get("timestamp")
        .and_then(Value::as_i64)
        .filter(|t| *t > 0)
        .ok_or_else(invalid_state)?;
    let updates: Vec<App> = match body.get_mut("updates").map(Value::take) {
        Some(Value::Array(list)) => list
            .into_iter()
            .filter(|v| v.is_object())
            .filter_map(|v| serde_json::from_value::<App>(v).ok())
            .filter_map(App::sanitised)
            .collect(),
        _ => Vec::new(),
    };
    let removes: Vec<String> = body
        .get("removes")
        .and_then(Value::as_array)
        .map(|list| list.iter().filter_map(Value::as_str).map(str::to_owned).collect())
        .unwrap_or_default();
    if updates.is_empty() && removes.is_empty() && timestamp == base.timestamp {
        return Ok(Outcome::Unchanged);
    }
    if updates.iter().any(|a| !a.category.is_empty() && !has_category(base, &a.category_key())) {
        return full(http, Some(base));
    }
    Ok(Outcome::Patch { timestamp, updates, removes })
}

fn has_category(catalog: &Catalog, key: &str) -> bool {
    catalog.categories.0.iter().any(|(k, _)| k.trim().to_lowercase() == key)
}
