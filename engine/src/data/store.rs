use crate::data::catalog::{Catalog, Latest, Listing};
use crate::data::data::{App, Categories, Index, Version};
use crate::data::helpers::lock;
use crate::data::sqlite::{connect, migrate, set_timestamp, write_app, CATALOG};
use crate::engine::resolver::Result;
use rusqlite::{params, Connection, OptionalExtension};
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::sync::Mutex;

const BLURB_CHARS: usize = 200;

pub struct Store {
    writer: Mutex<Connection>,
    reader: Mutex<Connection>,
}

impl Store {
    pub fn open(data_dir: &Path) -> Result<Self> {
        let path = data_dir.join("store.db");
        let store = match Self::open_at(&path) {
            Ok(store) => store,
            Err(_) => {
                for suffix in ["", "-wal", "-shm"] {
                    let _ = std::fs::remove_file(format!("{}{suffix}", path.display()));
                }
                Self::open_at(&path)?
            }
        };
        store.import_legacy(data_dir);
        Ok(store)
    }

    fn open_at(path: &Path) -> Result<Self> {
        let mut writer = connect(path)?;
        migrate(&mut writer)?;
        Ok(Self { writer: Mutex::new(writer), reader: Mutex::new(connect(path)?) })
    }

    fn import_legacy(&self, data_dir: &Path) {
        let legacy = data_dir.join("index.json");
        let _ = std::fs::remove_file(data_dir.join("index.json.tmp"));
        let Ok(file) = File::open(&legacy) else { return };
        let empty = lock(&self.reader)
            .query_row("SELECT NOT EXISTS(SELECT 1 FROM apps)", [], |r| r.get::<_, bool>(0))
            .unwrap_or(false);
        if empty {
            if let Ok(index) = serde_json::from_reader::<_, Index>(BufReader::new(file)) {
                if !index.apps.is_empty() && self.replace(&index).is_err() {
                    return;
                }
            }
        }
        let _ = std::fs::remove_file(&legacy);
    }

    pub fn catalog(&self) -> Result<Option<Catalog>> {
        let conn = lock(&self.reader);
        let Some(timestamp) = conn
            .query_row("SELECT value FROM meta WHERE key = 'timestamp'", [], |r| r.get::<_, i64>(0))
            .optional()?
        else {
            return Ok(None);
        };

        let categories = conn
            .prepare("SELECT key, label FROM categories ORDER BY pos")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<rusqlite::Result<Vec<(String, String)>>>()?;

        let apps = conn
            .prepare(CATALOG)?
            .query_map([], |r| {
                let package_name: String = r.get(0)?;
                let name: String = r.get(1)?;
                let summary = blurb(r.get(2)?, r.get(3)?);
                let haystack = format!("{name}\0{package_name}\0{summary}").to_lowercase();
                Ok(Listing {
                    repo_url: r.get(4)?,
                    trust_level: r.get(5)?,
                    category: r.get(6)?,
                    rating_avg: r.get(7)?,
                    rating_count: r.get(8)?,
                    icon_url: r.get(9)?,
                    signing_key_hash: r.get(10)?,
                    added: r.get(11)?,
                    versions: vec![Latest {
                        version_name: r.get(12)?,
                        version_code: r.get(13)?,
                        apk_size: r.get(14)?,
                        added: r.get(15)?,
                    }],
                    screenshots: r.get::<_, Option<String>>(16)?.into_iter().collect(),
                    package_name,
                    name,
                    summary,
                    haystack,
                })
            })?
            .collect::<rusqlite::Result<Vec<Listing>>>()?;

        if apps.is_empty() {
            return Ok(None);
        }
        Ok(Some(Catalog { timestamp, categories: Categories(categories), apps }))
    }

    pub fn app(&self, package: &str) -> Result<Option<App>> {
        let conn = lock(&self.reader);
        let Some(mut app) = conn
            .query_row(
                "SELECT name, summary, description, repo_url, trust_level, category, upstream,
                        rating_avg, rating_count, icon_url, signing_key_hash, added
                 FROM apps WHERE package_name = ?1",
                [package],
                |r| {
                    Ok(App {
                        package_name: package.to_owned(),
                        name: r.get(0)?,
                        summary: r.get(1)?,
                        description: r.get(2)?,
                        repo_url: r.get(3)?,
                        trust_level: r.get(4)?,
                        category: r.get(5)?,
                        upstream: r.get(6)?,
                        rating_avg: r.get(7)?,
                        rating_count: r.get(8)?,
                        icon_url: r.get(9)?,
                        signing_key_hash: r.get(10)?,
                        added: r.get(11)?,
                        ..Default::default()
                    })
                },
            )
            .optional()?
        else {
            return Ok(None);
        };
        app.versions = conn
            .prepare_cached(
                "SELECT version_name, version_code, apk_path, apk_size, sha256, scanned_at, added, whats_new
                 FROM versions WHERE package_name = ?1 ORDER BY version_code DESC",
            )?
            .query_map([package], |r| {
                Ok(Version {
                    version_name: r.get(0)?,
                    version_code: r.get(1)?,
                    apk_path: r.get(2)?,
                    apk_size: r.get(3)?,
                    sha256: r.get(4)?,
                    scanned_at: r.get(5)?,
                    added: r.get(6)?,
                    whats_new: r.get(7)?,
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        app.screenshots = conn
            .prepare_cached("SELECT url FROM screenshots WHERE package_name = ?1 ORDER BY pos")?
            .query_map([package], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        Ok(Some(app))
    }

    pub fn sha256(&self, package: &str, version_code: i64) -> Result<Option<String>> {
        Ok(lock(&self.reader)
            .query_row(
                "SELECT sha256 FROM versions WHERE package_name = ?1 AND version_code = ?2",
                params![package, version_code],
                |r| r.get(0),
            )
            .optional()?)
    }

    pub fn replace(&self, index: &Index) -> Result<()> {
        let mut conn = lock(&self.writer);
        let tx = conn.transaction()?;
        tx.execute_batch("DELETE FROM apps; DELETE FROM categories;")?;
        {
            let mut stmt = tx.prepare("INSERT INTO categories(key, label, pos) VALUES(?1, ?2, ?3)")?;
            for (pos, (key, label)) in index.categories.0.iter().enumerate() {
                stmt.execute(params![key, label, pos as i64])?;
            }
        }
        for app in &index.apps {
            write_app(&tx, app)?;
        }
        set_timestamp(&tx, index.timestamp)?;
        tx.commit()?;
        Ok(())
    }

    pub fn apply(&self, timestamp: i64, updates: &[App], removes: &[String]) -> Result<()> {
        let mut conn = lock(&self.writer);
        let tx = conn.transaction()?;
        {
            let mut stmt = tx.prepare("DELETE FROM apps WHERE package_name = ?1")?;
            for package in removes {
                stmt.execute([package])?;
            }
        }
        for app in updates {
            write_app(&tx, app)?;
        }
        set_timestamp(&tx, timestamp)?;
        tx.commit()?;
        Ok(())
    }
}

fn blurb(summary: String, description: Option<String>) -> String {
    match summary.trim() {
        "" => description.unwrap_or_default().trim().chars().take(BLURB_CHARS).collect(),
        text => text.to_owned(),
    }
}