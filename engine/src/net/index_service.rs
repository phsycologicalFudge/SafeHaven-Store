use crate::data::catalog::Catalog;
use crate::data::helpers::{lock, read, write};
use crate::data::store::Store;
use crate::engine::resolver::Result;
use crate::net::net::Http;
use crate::net::sync_service::{self, Outcome};
use std::path::Path;
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};

//settings
const TTL: Duration = Duration::from_secs(300);

//catalog cache
#[derive(Default)]
struct State {
    live: Option<Arc<Catalog>>,
    fresh_at: Option<Instant>,
}

pub struct IndexStore {
    state: RwLock<State>,
    gate: Mutex<()>,
    store: Store,
}

impl IndexStore {
    pub fn new(data_dir: &Path) -> Result<Self> {
        Ok(Self {
            state: RwLock::new(State::default()),
            gate: Mutex::new(()),
            store: Store::open(data_dir)?,
        })
    }

    pub fn store(&self) -> &Store {
        &self.store
    }

    fn fresh(&self, valid: impl Fn(Instant) -> bool) -> Option<Arc<Catalog>> {
        let state = read(&self.state);
        match (&state.live, state.fresh_at) {
            (Some(catalog), Some(at)) if valid(at) => Some(catalog.clone()),
            _ => None,
        }
    }

    fn baseline(&self) -> Option<Arc<Catalog>> {
        if let Some(catalog) = read(&self.state).live.clone() {
            return Some(catalog);
        }
        let catalog = Arc::new(self.store.catalog().ok()??);
        let mut state = write(&self.state);
        if state.live.is_none() {
            state.live = Some(catalog);
        }
        state.live.clone()
    }

    pub fn current(&self) -> Arc<Catalog> {
        self.baseline().unwrap_or_default()
    }

    pub fn fetch(&self, http: &Http, force: bool) -> Result<Arc<Catalog>> {
        if !force {
            if let Some(catalog) = self.fresh(|at| at.elapsed() < TTL) {
                return Ok(catalog);
            }
        }
        let started = Instant::now();
        let _gate = lock(&self.gate);
        if let Some(catalog) = self.fresh(|at| at >= started) {
            return Ok(catalog);
        }
        let baseline = self.baseline();
        let changed = match sync_service::sync_store(http, baseline.as_deref())? {
            Outcome::Full(index) => {
                self.store.replace(&index)?;
                true
            }
            Outcome::Patch { timestamp, updates, removes } => {
                self.store.apply(timestamp, &updates, &removes)?;
                true
            }
            Outcome::Unchanged => false,
        };
        let catalog = match baseline {
            Some(base) if !changed => base,
            _ => Arc::new(self.store.catalog()?.unwrap_or_default()),
        };
        let mut state = write(&self.state);
        state.live = Some(catalog.clone());
        state.fresh_at = Some(Instant::now());
        Ok(catalog)
    }
}
