use crate::data::catalog::{Catalog, Listing};
use std::collections::{HashMap, HashSet};
use std::f64::consts::LN_10;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

//settings
const MAX_RECENCY_BOOST: f64 = 1.5;
const RECENCY_WINDOW_SECS: i64 = 30 * 86400;
const HOUSE_PREFIX: &str = "com.colourswift.";

//random source
static SALT: AtomicU64 = AtomicU64::new(0x9E37_79B9_7F4A_7C15);

pub struct Rng(u64);

impl Rng {
    pub fn new() -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(1);
        let salt = SALT.fetch_add(0x9E37_79B9_7F4A_7C15, Ordering::Relaxed);
        Self((nanos ^ salt).max(1))
    }

    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    pub fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }

    pub fn shuffle<T>(&mut self, items: &mut [T]) {
        for i in (1..items.len()).rev() {
            let j = self.below(i + 1);
            items.swap(i, j);
        }
    }

    fn random_limit(&mut self) -> usize {
        5 + self.below(6)
    }
}

pub fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

pub fn pool<'a>(catalog: &'a Catalog, category: &str) -> Vec<&'a Listing> {
    let key = category.trim().to_lowercase();
    catalog
        .apps
        .iter()
        .filter(|a| key.is_empty() || a.category_key() == key)
        .collect()
}

pub fn by_packages<'a>(catalog: &'a Catalog, names: &[String]) -> Vec<&'a Listing> {
    let lookup: HashMap<&str, &Listing> = catalog.apps.iter().map(|a| (a.package_name.as_str(), a)).collect();
    let mut seen = HashSet::new();
    names
        .iter()
        .filter(|n| seen.insert(n.as_str()))
        .filter_map(|n| lookup.get(n.as_str()).copied())
        .collect()
}

pub fn search<'a>(apps: Vec<&'a Listing>, query: &str, min_rating: f64) -> Vec<&'a Listing> {
    let needle = query.trim().to_lowercase();
    let filtered = apps.into_iter().filter(|a| a.rating_avg >= min_rating);
    if needle.is_empty() {
        return filtered.collect();
    }
    let tokens: Vec<&str> = needle.split_whitespace().collect();
    let mut scored: Vec<(u32, f64, usize, &Listing)> = filtered
        .filter_map(|a| {
            let score = relevance(&a.haystack, &needle, &tokens)?;
            Some((score, rating_score(a), a.name.len(), a))
        })
        .collect();
    scored.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.total_cmp(&a.1)).then(a.2.cmp(&b.2)));
    scored.into_iter().map(|(_, _, _, a)| a).collect()
}

fn relevance(haystack: &str, needle: &str, tokens: &[&str]) -> Option<u32> {
    let mut parts = haystack.splitn(3, '\0');
    let name = parts.next().unwrap_or("");
    let package = parts.next().unwrap_or("");
    let summary = parts.next().unwrap_or("");
    let leaf = package.rsplit('.').next().unwrap_or("");

    if let Some(score) = phrase_score(name, package, leaf, summary, needle) {
        return Some(score);
    }
    if tokens.len() < 2 || !tokens.iter().all(|t| haystack.contains(t)) {
        return None;
    }
    let total: u32 = tokens
        .iter()
        .map(|t| phrase_score(name, package, leaf, summary, t).unwrap_or(0))
        .sum();
    Some(total / tokens.len() as u32 / 2)
}

fn phrase_score(name: &str, package: &str, leaf: &str, summary: &str, needle: &str) -> Option<u32> {
    if name == needle {
        Some(1000)
    } else if name.starts_with(needle) {
        Some(900)
    } else if words(name).any(|w| w.starts_with(needle)) {
        Some(800)
    } else if name.contains(needle) {
        Some(700)
    } else if leaf == needle {
        Some(600)
    } else if leaf.starts_with(needle) {
        Some(550)
    } else if package.contains(needle) {
        Some(400)
    } else if words(summary).any(|w| w.starts_with(needle)) {
        Some(300)
    } else if summary.contains(needle) {
        Some(200)
    } else {
        None
    }
}

fn words(text: &str) -> impl Iterator<Item = &str> {
    text.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty())
}

pub fn rating_score(app: &Listing) -> f64 {
    if app.rating_count <= 0 || app.rating_avg <= 0.0 {
        return 0.0;
    }
    app.rating_avg * ((app.rating_count + 1) as f64).ln() / LN_10
}

fn trending_score(app: &Listing, now: i64) -> f64 {
    let base = rating_score(app);
    let added = app.latest().map(|v| v.added).unwrap_or(0);
    if added <= 0 {
        return 0.0;
    }
    let age_days = (now - added) as f64 / 86400.0;
    if age_days <= 0.0 {
        return base;
    }
    base / (age_days + 2.0).powf(1.5)
}

fn recency_boost(app: &Listing, now: i64) -> f64 {
    let added = app.latest().map(|v| v.added).unwrap_or(0);
    if added <= 0 {
        return 0.0;
    }
    let age = now - added;
    if age <= 0 {
        return MAX_RECENCY_BOOST;
    }
    if age >= RECENCY_WINDOW_SECS {
        return 0.0;
    }
    MAX_RECENCY_BOOST * (1.0 - age as f64 / RECENCY_WINDOW_SECS as f64)
}

fn sort_desc(apps: &mut Vec<&Listing>, key: impl Fn(&Listing) -> f64) {
    let mut keyed: Vec<(f64, &Listing)> = apps.iter().map(|a| (key(a), *a)).collect();
    keyed.sort_by(|a, b| b.0.total_cmp(&a.0));
    *apps = keyed.into_iter().map(|(_, a)| a).collect();
}

//rankings
pub fn top_charts<'a>(mut apps: Vec<&'a Listing>, limit: Option<usize>, rng: &mut Rng, now: i64) -> Vec<&'a Listing> {
    rng.shuffle(&mut apps);
    sort_desc(&mut apps, |a| trending_score(a, now));
    for i in 0..3.min(apps.len()) {
        if apps[i].package_name.starts_with(HOUSE_PREFIX) {
            if let Some(j) = (i + 1..apps.len()).find(|&j| !apps[j].package_name.starts_with(HOUSE_PREFIX)) {
                apps.swap(i, j);
            }
        }
    }
    let take = limit.unwrap_or_else(|| rng.random_limit());
    apps.truncate(take);
    apps
}

pub fn recommended<'a>(
    apps: Vec<&'a Listing>,
    exclude: &HashSet<String>,
    dominant: Option<&str>,
    limit: Option<usize>,
    rng: &mut Rng,
    now: i64,
) -> Vec<&'a Listing> {
    let target = limit.unwrap_or_else(|| rng.random_limit());
    let pool: Vec<&Listing> = apps.into_iter().filter(|a| !exclude.contains(&a.package_name)).collect();
    if pool.is_empty() {
        return Vec::new();
    }

    let mut selected: Vec<&Listing> = Vec::new();
    if let Some(category) = dominant {
        let mut in_category: Vec<&Listing> = pool.iter().copied().filter(|a| a.category_key() == category).collect();
        rng.shuffle(&mut in_category);
        sort_desc(&mut in_category, rating_score);
        let mut sample: Vec<&Listing> = in_category.into_iter().take(3).collect();
        rng.shuffle(&mut sample);
        selected.extend(sample.into_iter().take(2.min(target)));
    }

    let chosen: HashSet<&str> = selected.iter().map(|a| a.package_name.as_str()).collect();
    let mut fill: Vec<&Listing> = pool.into_iter().filter(|a| !chosen.contains(a.package_name.as_str())).collect();
    rng.shuffle(&mut fill);
    sort_desc(&mut fill, |a| rating_score(a) + recency_boost(a, now));
    fill.truncate(target.saturating_mul(2));
    rng.shuffle(&mut fill);
    selected.extend(fill);
    selected.truncate(target);
    selected
}

pub fn new_arrivals(mut apps: Vec<&Listing>, limit: usize) -> Vec<&Listing> {
    apps.sort_by_key(|a| std::cmp::Reverse(a.released_at()));
    apps.truncate(limit);
    apps
}

pub fn top_rated(mut apps: Vec<&Listing>, limit: usize) -> Vec<&Listing> {
    sort_desc(&mut apps, rating_score);
    apps.truncate(limit);
    apps
}