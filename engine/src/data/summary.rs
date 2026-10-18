use crate::data::data::{App, Categories, Index};
use serde::Serialize;
use std::borrow::Cow;

const BLURB_CHARS: usize = 200;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VersionSummary<'a> {
    version_name: &'a str,
    version_code: i64,
    apk_size: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSummary<'a> {
    package_name: &'a str,
    name: &'a str,
    summary: Cow<'a, str>,
    repo_url: &'a str,
    trust_level: &'a str,
    category: &'a str,
    rating_avg: f64,
    rating_count: i64,
    icon_url: Option<&'a str>,
    screenshots: &'a [String],
    signing_key_hash: Option<&'a str>,
    versions: Vec<VersionSummary<'a>>,
}

#[derive(Serialize)]
pub struct IndexSummary<'a> {
    timestamp: i64,
    categories: &'a Categories,
    apps: Vec<AppSummary<'a>>,
}

impl<'a> AppSummary<'a> {
    pub fn of(app: &'a App) -> Self {
        let summary = match app.summary.trim() {
            "" => Cow::Owned(app.description.trim().chars().take(BLURB_CHARS).collect()),
            text => Cow::Borrowed(text),
        };
        Self {
            package_name: &app.package_name,
            name: &app.name,
            summary,
            repo_url: &app.repo_url,
            trust_level: &app.trust_level,
            category: &app.category,
            rating_avg: app.rating_avg,
            rating_count: app.rating_count,
            icon_url: app.icon_url.as_deref(),
            screenshots: &app.screenshots[..app.screenshots.len().min(1)],
            signing_key_hash: app.signing_key_hash.as_deref(),
            versions: app
                .latest_version()
                .map(|v| VersionSummary {
                    version_name: &v.version_name,
                    version_code: v.version_code,
                    apk_size: v.apk_size,
                })
                .into_iter()
                .collect(),
        }
    }
}

impl<'a> IndexSummary<'a> {
    pub fn of(index: &'a Index) -> Self {
        Self {
            timestamp: index.timestamp,
            categories: &index.categories,
            apps: index.apps.iter().map(|a| AppSummary::of(a)).collect(),
        }
    }
}

pub fn summaries<'a>(apps: Vec<&'a App>) -> Vec<AppSummary<'a>> {
    apps.into_iter().map(AppSummary::of).collect()
}
