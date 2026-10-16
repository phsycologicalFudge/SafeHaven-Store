use crate::data::helpers::{self, skip_scalars, skip_seq, Scalar};
use serde::de::{Deserializer, MapAccess, Visitor};
use serde::{Deserialize, Serialize, Serializer};
use std::fmt;
use std::sync::{Arc, OnceLock};

//image urls
const DEFAULT_CDN: &str = "https://api.colourswift.com/store/img";

static CDN_BASE: OnceLock<String> = OnceLock::new();

pub fn set_cdn_base(base_url: &str) {
    let _ = CDN_BASE.set(format!("{}/store/img", base_url.trim_end_matches('/')));
}

fn cdn_base() -> &'static str {
    CDN_BASE.get().map(String::as_str).unwrap_or(DEFAULT_CDN)
}

pub fn normalise_image_url(url: Option<String>) -> Option<String> {
    let url = url.filter(|u| !u.is_empty())?;
    if url.contains("/store/img/") {
        return Some(url);
    }
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"));
    let Some(rest) = rest else { return Some(url) };
    let Some((host, path)) = rest.split_once('/') else { return Some(url) };
    let host_ok = host
        .strip_suffix(".your-objectstorage.com")
        .is_some_and(|h| !h.is_empty() && !h.contains('/'));
    if !host_ok {
        return Some(url);
    }
    let Some((bucket, key)) = path.split_once('/') else { return Some(url) };
    if bucket.is_empty() || key.is_empty() || !key.starts_with("images/") {
        return Some(url);
    }
    Some(format!("{}/{}", cdn_base(), key))
}

fn image_url<'de, D: Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    helpers::nullable_string(d).map(normalise_image_url)
}

fn screenshots<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<String>, D::Error> {
    helpers::text_list(d).map(|list| {
        list.into_iter()
            .filter_map(|s| normalise_image_url(Some(s)))
            .collect()
    })
}

//app model
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Version {
    #[serde(default, deserialize_with = "helpers::string")]
    pub version_name: String,
    #[serde(default, deserialize_with = "helpers::int")]
    pub version_code: i64,
    #[serde(default, deserialize_with = "helpers::string")]
    pub apk_path: String,
    #[serde(default, deserialize_with = "helpers::int")]
    pub apk_size: i64,
    #[serde(default, deserialize_with = "helpers::string")]
    pub sha256: String,
    #[serde(default, deserialize_with = "helpers::int")]
    pub scanned_at: i64,
    #[serde(default, deserialize_with = "helpers::int")]
    pub added: i64,
    #[serde(default, deserialize_with = "helpers::nullable_string")]
    pub whats_new: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct App {
    #[serde(default, deserialize_with = "helpers::string")]
    pub package_name: String,
    #[serde(default, deserialize_with = "helpers::string")]
    pub name: String,
    #[serde(default, deserialize_with = "helpers::string")]
    pub summary: String,
    #[serde(default, deserialize_with = "helpers::string")]
    pub description: String,
    #[serde(default, deserialize_with = "helpers::string")]
    pub repo_url: String,
    #[serde(default, deserialize_with = "helpers::trust_level")]
    pub trust_level: String,
    #[serde(default, deserialize_with = "helpers::string")]
    pub category: String,
    #[serde(default, deserialize_with = "helpers::string")]
    pub upstream: String,
    #[serde(default, deserialize_with = "helpers::float")]
    pub rating_avg: f64,
    #[serde(default, deserialize_with = "helpers::int")]
    pub rating_count: i64,
    #[serde(default, deserialize_with = "helpers::list")]
    pub versions: Vec<Version>,
    #[serde(default, deserialize_with = "image_url")]
    pub icon_url: Option<String>,
    #[serde(default, deserialize_with = "screenshots")]
    pub screenshots: Vec<String>,
    #[serde(default, deserialize_with = "helpers::nullable_string")]
    pub signing_key_hash: Option<String>,
    #[serde(default, deserialize_with = "helpers::int")]
    pub added: i64,
}

impl App {
    pub fn sanitised(mut self) -> Option<Self> {
        self.package_name = self.package_name.trim().to_owned();
        self.versions
            .retain(|v| v.version_code > 0 && v.apk_size > 0 && !v.apk_path.is_empty());
        (!self.package_name.is_empty() && !self.versions.is_empty()).then_some(self)
    }

    pub fn category_key(&self) -> String {
        self.category.trim().to_lowercase()
    }
}

//the index parsing
fn apps<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<Arc<App>>, D::Error> {
    helpers::list::<D, App>(d).map(|list| {
        list.into_iter()
            .filter_map(App::sanitised)
            .map(Arc::new)
            .collect()
    })
}

#[derive(Clone, Debug, Default)]
pub struct Categories(pub Vec<(String, String)>);

impl Serialize for Categories {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_map(self.0.iter().map(|(k, v)| (k, v)))
    }
}

struct CategoriesVisitor;

impl<'de> Visitor<'de> for CategoriesVisitor {
    type Value = Categories;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a category map")
    }

    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Categories, A::Error> {
        let mut out = Vec::new();
        while let Some((k, v)) = map.next_entry::<String, Scalar>()? {
            out.push((k, v.into_string()));
        }
        Ok(Categories(out))
    }

    skip_scalars!(Categories);
    skip_seq!(Categories);
}

impl<'de> Deserialize<'de> for Categories {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_any(CategoriesVisitor)
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Index {
    #[serde(default, deserialize_with = "helpers::int")]
    pub timestamp: i64,
    #[serde(default)]
    pub categories: Categories,
    #[serde(default, deserialize_with = "apps")]
    pub apps: Vec<Arc<App>>,
}
