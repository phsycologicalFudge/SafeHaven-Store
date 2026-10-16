use crate::data::data::Categories;
use serde::Serialize;

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Latest {
    pub version_name: String,
    pub version_code: i64,
    pub apk_size: i64,
    #[serde(skip)]
    pub added: i64,
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Listing {
    pub package_name: String,
    pub name: String,
    pub summary: String,
    pub repo_url: String,
    pub trust_level: String,
    pub category: String,
    pub rating_avg: f64,
    pub rating_count: i64,
    pub icon_url: Option<String>,
    pub screenshots: Vec<String>,
    pub signing_key_hash: Option<String>,
    pub versions: Vec<Latest>,
    #[serde(skip)]
    pub added: i64,
    #[serde(skip)]
    pub haystack: String,
}

impl Listing {
    pub fn latest(&self) -> Option<&Latest> {
        self.versions.first()
    }

    pub fn released_at(&self) -> i64 {
        if self.added > 0 {
            return self.added;
        }
        self.latest().map_or(0, |v| v.added)
    }

    pub fn category_key(&self) -> String {
        self.category.trim().to_lowercase()
    }
}

#[derive(Clone, Debug, Default)]
pub struct Catalog {
    pub timestamp: i64,
    pub categories: Categories,
    pub apps: Vec<Listing>,
}
