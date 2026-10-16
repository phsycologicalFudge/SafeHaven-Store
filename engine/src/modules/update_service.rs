use crate::engine::resolver::Result;
use crate::data::helpers::{self, lock};
use crate::data::catalog::{Catalog, Listing};
use crate::net::net::Http;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

//settings
const URL_FANOUT: usize = 8;

//types
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Installed {
    #[serde(default, deserialize_with = "helpers::strict_true")]
    pub installed: bool,
    #[serde(default, deserialize_with = "helpers::int")]
    pub version_code: i64,
    #[serde(default, deserialize_with = "helpers::nullable_string")]
    pub signing_certificate_sha256: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckItem {
    pub package_name: String,
    pub latest_version_code: Option<i64>,
    pub signing_key_hash: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckResult {
    pub package_name: String,
    pub status: &'static str,
    pub signature_mismatch: Option<bool>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstalledCheck<'a> {
    pub app: &'a Listing,
    pub status: &'static str,
    pub signature_mismatch: Option<bool>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanEntry {
    pub package_name: String,
    pub version_code: i64,
    pub download_url: String,
}

//sig n status checks
fn clean(value: &Option<String>) -> Option<String> {
    value.as_ref().map(|s| s.trim().to_lowercase()).filter(|s| !s.is_empty())
}

pub fn signature_mismatch(state: &Installed, store_hash: &Option<String>) -> Option<bool> {
    Some(clean(&state.signing_certificate_sha256)? != clean(store_hash)?)
}

pub fn resolve_status(state: &Installed, latest: Option<i64>) -> &'static str {
    if !state.installed {
        return "notInstalled";
    }
    match latest {
        None => "missingStoreVersion",
        Some(code) if code > state.version_code => "updateAvailable",
        Some(code) if code == state.version_code => "current",
        Some(_) => "installedNewerThanStore",
    }
}

pub fn check(states: &HashMap<String, Installed>, items: Vec<CheckItem>) -> Vec<CheckResult> {
    let absent = Installed::default();
    items
        .into_iter()
        .map(|item| {
            let state = states.get(&item.package_name).unwrap_or(&absent);
            CheckResult {
                status: resolve_status(state, item.latest_version_code),
                signature_mismatch: signature_mismatch(state, &item.signing_key_hash),
                package_name: item.package_name,
            }
        })
        .collect()
}

pub fn installed<'a>(catalog: &'a Catalog, states: &HashMap<String, Installed>) -> Vec<InstalledCheck<'a>> {
    catalog
        .apps
        .iter()
        .filter_map(|app| {
            let state = states.get(&app.package_name).filter(|s| s.installed)?;
            Some(InstalledCheck {
                status: resolve_status(state, app.latest().map(|v| v.version_code)),
                signature_mismatch: signature_mismatch(state, &app.signing_key_hash),
                app,
            })
        })
        .collect()
}

//update planning
pub fn plan(
    http: &Http,
    catalog: &Catalog,
    states: &HashMap<String, Installed>,
    triggered: Option<HashMap<String, i64>>,
) -> Result<Vec<PlanEntry>> {
    let mut eligible: Vec<(&str, i64)> = Vec::new();

    for app in &catalog.apps {
        let Some(latest) = app.latest() else { continue };
        if triggered.as_ref().is_some_and(|t| t.get(&app.package_name) == Some(&latest.version_code)) {
            continue;
        }
        let Some(state) = states.get(&app.package_name) else { continue };
        if !state.installed || latest.version_code <= state.version_code {
            continue;
        }
        if signature_mismatch(state, &app.signing_key_hash) == Some(true) {
            continue;
        }
        eligible.push((app.package_name.as_str(), latest.version_code));
    }

    let next = AtomicUsize::new(0);
    let done: Mutex<Vec<(usize, Result<PlanEntry>)>> = Mutex::new(Vec::new());
    std::thread::scope(|scope| {
        for _ in 0..URL_FANOUT.min(eligible.len()) {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                let Some(&(pkg, code)) = eligible.get(i) else { break };
                let entry = http.download_url(pkg, code).map(|download_url| PlanEntry {
                    package_name: pkg.to_owned(),
                    version_code: code,
                    download_url,
                });
                lock(&done).push((i, entry));
            });
        }
    });

    let mut done = done.into_inner().unwrap_or_else(|e| e.into_inner());
    done.sort_by_key(|(i, _)| *i);
    let mut entries = Vec::with_capacity(done.len());
    let mut first_error = None;
    for (_, result) in done {
        match result {
            Ok(entry) => entries.push(entry),
            Err(e) => {
                first_error.get_or_insert(e);
            }
        }
    }
    match first_error {
        Some(e) if entries.is_empty() => Err(e),
        _ => Ok(entries),
    }
}
