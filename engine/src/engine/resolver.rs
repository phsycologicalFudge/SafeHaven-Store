use crate::engine::engine;
use crate::modules::download_service::StartArgs;
use crate::modules::rank_service::{self as rank, Rng};
use crate::modules::update_service::{self as update, CheckItem, Installed};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fmt;

//arg shapes
#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Force {
    force: bool,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Package {
    package: String,
    cached: bool,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Scope {
    packages: Vec<String>,
    exclude: Vec<String>,
    category: String,
    query: String,
    min_rating: f64,
    dominant_category: Option<String>,
    limit: Option<usize>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Check {
    states: HashMap<String, Installed>,
    items: Vec<CheckItem>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Plan {
    states: HashMap<String, Installed>,
    triggered: Option<HashMap<String, i64>>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Job {
    id: Option<u64>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Request {
    method: String,
    path: String,
    token: Option<String>,
    body: Option<serde_json::Value>,
}

//helpers
fn json<T: Serialize>(value: &T) -> Result<String> {
    Ok(serde_json::to_string(value)?)
}

fn parse<T: DeserializeOwned>(raw: &str) -> Result<T> {
    Ok(serde_json::from_str(if raw.trim().is_empty() { "{}" } else { raw })?)
}

//method dispatch
pub fn call(method: &str, raw: &str) -> Result<String> {
    let engine = engine::get()?;

    match method {
        "index.get" => {
            let catalog = engine.index.fetch(&engine.http, parse::<Force>(raw)?.force)?;
            Ok(serde_json::json!({
                "timestamp": catalog.timestamp,
                "categories": &catalog.categories,
                "count": catalog.apps.len(),
            })
            .to_string())
        }
        "index.sync" => {
            let catalog = engine.index.fetch(&engine.http, parse::<Force>(raw)?.force)?;
            Ok(format!(r#"{{"timestamp":{},"count":{}}}"#, catalog.timestamp, catalog.apps.len()))
        }
        "index.app" => {
            let Package { package, cached } = parse(raw)?;
            if !cached {
                engine.index.fetch(&engine.http, false)?;
            }
            json(&engine.index.store().app(&package)?.ok_or_else(|| EngineError::new("not_in_index"))?)
        }
        "index.apps" => {
            let scope: Scope = parse(raw)?;
            json(&rank::by_packages(&engine.index.current(), &scope.packages))
        }
        "index.query" => {
            let scope: Scope = parse(raw)?;
            let catalog = engine.index.current();
            json(&rank::search(rank::pool(&catalog, &scope.category), &scope.query, scope.min_rating))
        }
        "index.new_arrivals" => {
            let scope: Scope = parse(raw)?;
            let catalog = engine.index.current();
            json(&rank::new_arrivals(rank::pool(&catalog, &scope.category), scope.limit.unwrap_or(10)))
        }
        "index.top_in_category" => {
            let scope: Scope = parse(raw)?;
            let catalog = engine.index.current();
            json(&rank::top_rated(rank::pool(&catalog, &scope.category), scope.limit.unwrap_or(8)))
        }
        "rank.top_charts" => {
            let scope: Scope = parse(raw)?;
            let catalog = engine.index.current();
            let pool = rank::pool(&catalog, &scope.category);
            json(&rank::top_charts(pool, scope.limit, &mut Rng::new(), rank::now_secs()))
        }
        "rank.recommended" => {
            let scope: Scope = parse(raw)?;
            let catalog = engine.index.current();
            let pool = rank::pool(&catalog, &scope.category);
            let exclude: HashSet<String> = scope.exclude.into_iter().collect();
            let dominant = scope.dominant_category.map(|c| c.trim().to_lowercase());
            json(&rank::recommended(
                pool,
                &exclude,
                dominant.as_deref(),
                scope.limit,
                &mut Rng::new(),
                rank::now_secs(),
            ))
        }
        "updates.check" => {
            let check: Check = parse(raw)?;
            json(&update::check(&check.states, check.items))
        }
        "updates.installed" => {
            let check: Check = parse(raw)?;
            json(&update::installed(&engine.index.current(), &check.states))
        }
        "updates.plan" => {
            let plan: Plan = parse(raw)?;
            let catalog = engine.index.current();
            json(&update::plan(&engine.http, &catalog, &plan.states, plan.triggered)?)
        }
        "download.start" => {
            let mut args: StartArgs = parse(raw)?;
            if args.sha256.is_none() {
                args.sha256 = engine.index.store().sha256(&args.package_name, args.version_code)?;
            }
            Ok(engine.downloads.start(&engine.http, args)?.to_string())
        }
        "download.status" => {
            let id = parse::<Job>(raw)?.id.ok_or_else(|| EngineError::new("missing_id"))?;
            json(&engine.downloads.status(id)?)
        }
        "download.pause" => Ok(engine.downloads.pause(parse::<Job>(raw)?.id).to_string()),
        "download.resume" => Ok(engine.downloads.resume(parse::<Job>(raw)?.id).to_string()),
        "download.cancel" => Ok(engine.downloads.cancel(parse::<Job>(raw)?.id).to_string()),
        "api.request" => {
            let request: Request = parse(raw)?;
            json(&engine.http.send(&request.method, &request.path, request.token.as_deref(), request.body.as_ref())?)
        }
        _ => Err(EngineError::new(format!("unknown_method_{method}"))),
    }
}

//errors
#[derive(Debug, Clone)]
pub struct EngineError(pub String);

impl EngineError {
    pub fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for EngineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for EngineError {}

impl From<std::io::Error> for EngineError {
    fn from(e: std::io::Error) -> Self {
        Self(format!("io_{e}"))
    }
}

impl From<serde_json::Error> for EngineError {
    fn from(e: serde_json::Error) -> Self {
        Self(format!("json_{e}"))
    }
}

impl From<rusqlite::Error> for EngineError {
    fn from(e: rusqlite::Error) -> Self {
        Self(format!("db_{e}"))
    }
}

impl From<ureq::Error> for EngineError {
    fn from(e: ureq::Error) -> Self {
        Self(format!("network_{e}"))
    }
}

pub type Result<T> = std::result::Result<T, EngineError>;
