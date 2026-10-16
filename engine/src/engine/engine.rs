use crate::modules::download_service::Downloads;
use crate::engine::resolver::{EngineError, Result};
use crate::net::index_service::IndexStore;
use crate::data::data::set_cdn_base;
use crate::net::net::Http;
use std::path::Path;
use std::sync::OnceLock;

pub struct Engine {
    pub http: Http,
    pub index: IndexStore,
    pub downloads: Downloads,
}

static ENGINE: OnceLock<Engine> = OnceLock::new();

pub fn init(base_url: &str, data_dir: &str) -> Result<()> {
    if ENGINE.get().is_some() {
        return Ok(());
    }
    let dir = Path::new(data_dir);
    std::fs::create_dir_all(dir)?;
    set_cdn_base(base_url);
    let _ = ENGINE.set(Engine {
        http: Http::new(base_url),
        index: IndexStore::new(dir)?,
        downloads: Downloads::new(dir),
    });
    Ok(())
}

pub fn get() -> Result<&'static Engine> {
    ENGINE.get().ok_or_else(|| EngineError::new("engine_not_initialised"))
}
