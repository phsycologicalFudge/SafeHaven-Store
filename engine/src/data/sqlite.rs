use crate::data::data::App;
use crate::engine::resolver::Result;
use rusqlite::{params, Connection, Transaction};
use std::path::Path;
use std::time::Duration;

const SCHEMA_VERSION: i64 = 1;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS meta(
    key TEXT PRIMARY KEY,
    value INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS categories(
    key TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    pos INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS apps(
    package_name TEXT PRIMARY KEY,
    pos INTEGER NOT NULL,
    name TEXT NOT NULL,
    summary TEXT NOT NULL,
    description TEXT NOT NULL,
    repo_url TEXT NOT NULL,
    trust_level TEXT NOT NULL,
    category TEXT NOT NULL,
    upstream TEXT NOT NULL,
    rating_avg REAL NOT NULL,
    rating_count INTEGER NOT NULL,
    icon_url TEXT,
    signing_key_hash TEXT,
    added INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS versions(
    package_name TEXT NOT NULL REFERENCES apps(package_name) ON DELETE CASCADE,
    version_code INTEGER NOT NULL,
    version_name TEXT NOT NULL,
    apk_path TEXT NOT NULL,
    apk_size INTEGER NOT NULL,
    sha256 TEXT NOT NULL,
    scanned_at INTEGER NOT NULL,
    added INTEGER NOT NULL,
    whats_new TEXT,
    PRIMARY KEY(package_name, version_code)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS screenshots(
    package_name TEXT NOT NULL REFERENCES apps(package_name) ON DELETE CASCADE,
    pos INTEGER NOT NULL,
    url TEXT NOT NULL,
    PRIMARY KEY(package_name, pos)
) WITHOUT ROWID;
";

const UPSERT_APP: &str = "
INSERT INTO apps(package_name, pos, name, summary, description, repo_url, trust_level, category,
                 upstream, rating_avg, rating_count, icon_url, signing_key_hash, added)
VALUES(?1, COALESCE((SELECT pos FROM apps WHERE package_name = ?1),
                    (SELECT IFNULL(MAX(pos), -1) + 1 FROM apps)),
       ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
ON CONFLICT(package_name) DO UPDATE SET
    name = excluded.name,
    summary = excluded.summary,
    description = excluded.description,
    repo_url = excluded.repo_url,
    trust_level = excluded.trust_level,
    category = excluded.category,
    upstream = excluded.upstream,
    rating_avg = excluded.rating_avg,
    rating_count = excluded.rating_count,
    icon_url = excluded.icon_url,
    signing_key_hash = excluded.signing_key_hash,
    added = excluded.added
";

const INSERT_VERSION: &str = "
INSERT OR REPLACE INTO versions(package_name, version_code, version_name, apk_path, apk_size,
                                sha256, scanned_at, added, whats_new)
VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
";

pub(crate) const CATALOG: &str = "
SELECT a.package_name, a.name, a.summary,
       CASE WHEN trim(a.summary, ' ' || char(9, 10, 13)) = '' THEN substr(a.description, 1, 1000) END,
       a.repo_url, a.trust_level, a.category, a.rating_avg, a.rating_count, a.icon_url,
       a.signing_key_hash, a.added, v.version_name, v.version_code, v.apk_size, v.added,
       (SELECT url FROM screenshots s WHERE s.package_name = a.package_name ORDER BY s.pos LIMIT 1)
FROM apps a
JOIN versions v ON v.package_name = a.package_name
 AND v.version_code = (SELECT MAX(version_code) FROM versions m WHERE m.package_name = a.package_name)
ORDER BY a.pos
";

pub(crate) fn connect(path: &Path) -> Result<Connection> {
    let conn = Connection::open(path)?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA foreign_keys = ON;
         PRAGMA temp_store = MEMORY;",
    )?;
    Ok(conn)
}

pub(crate) fn migrate(conn: &mut Connection) -> Result<()> {
    let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if version == SCHEMA_VERSION {
        return Ok(());
    }
    let tx = conn.transaction()?;
    if version > SCHEMA_VERSION {
        tx.execute_batch(
            "DROP TABLE IF EXISTS screenshots; DROP TABLE IF EXISTS versions;
             DROP TABLE IF EXISTS apps; DROP TABLE IF EXISTS categories; DROP TABLE IF EXISTS meta;",
        )?;
    }
    tx.execute_batch(SCHEMA)?;
    tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    tx.commit()?;
    Ok(())
}

pub(crate) fn set_timestamp(tx: &Transaction, timestamp: i64) -> Result<()> {
    tx.execute(
        "INSERT INTO meta(key, value) VALUES('timestamp', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [timestamp],
    )?;
    Ok(())
}

pub(crate) fn write_app(tx: &Transaction, app: &App) -> Result<()> {
    tx.prepare_cached(UPSERT_APP)?.execute(params![
        app.package_name,
        app.name,
        app.summary,
        app.description,
        app.repo_url,
        app.trust_level,
        app.category,
        app.upstream,
        app.rating_avg,
        app.rating_count,
        app.icon_url,
        app.signing_key_hash,
        app.added,
    ])?;
    tx.prepare_cached("DELETE FROM versions WHERE package_name = ?1")?
        .execute([&app.package_name])?;
    tx.prepare_cached("DELETE FROM screenshots WHERE package_name = ?1")?
        .execute([&app.package_name])?;

    let mut insert_version = tx.prepare_cached(INSERT_VERSION)?;
    for v in &app.versions {
        insert_version.execute(params![
            app.package_name,
            v.version_code,
            v.version_name,
            v.apk_path,
            v.apk_size,
            v.sha256,
            v.scanned_at,
            v.added,
            v.whats_new,
        ])?;
    }

    let mut insert_shot =
        tx.prepare_cached("INSERT INTO screenshots(package_name, pos, url) VALUES(?1, ?2, ?3)")?;
    for (pos, url) in app.screenshots.iter().enumerate() {
        insert_shot.execute(params![app.package_name, pos as i64, url])?;
    }
    Ok(())
}