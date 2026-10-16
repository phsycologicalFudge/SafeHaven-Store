use crate::engine::resolver::{EngineError, Result};
use crate::data::helpers::lock;
use crate::net::net::Http;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::io::{BufWriter, Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, RecvTimeoutError};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

//states and limits
const QUEUED: u8 = 0;
const RUNNING: u8 = 1;
const DONE: u8 = 2;
const FAILED: u8 = 3;
const CHUNK: usize = 64 * 1024;
const CANCELLED: &str = "download_cancelled";
const STALL: Duration = Duration::from_secs(60);
const POLL: Duration = Duration::from_millis(100);
const BACKLOG: usize = 8;
const BACKSTOP: Duration = Duration::from_secs(2 * 3600);
const CACHE_TTL: Duration = Duration::from_secs(900);

//job types
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StartArgs {
    pub package_name: String,
    pub version_code: i64,
    #[serde(default)]
    pub apk_size: i64,
    #[serde(default)]
    pub sha256: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct Status {
    pub state: &'static str,
    pub received: u64,
    pub total: u64,
    pub error: Option<String>,
    pub path: Option<String>,
}

struct Job {
    state: AtomicU8,
    received: AtomicU64,
    total: AtomicU64,
    paused: AtomicBool,
    cancelled: AtomicBool,
    error: Mutex<Option<String>>,
    path: Mutex<Option<String>>,
}

struct Queue {
    line: Mutex<VecDeque<u64>>,
    changed: Condvar,
}

struct TurnGuard<'a> {
    queue: &'a Queue,
}

impl Drop for TurnGuard<'_> {
    fn drop(&mut self) {
        lock(&self.queue.line).pop_front();
        self.queue.changed.notify_all();
    }
}

pub struct Downloads {
    jobs: Mutex<HashMap<u64, Arc<Job>>>,
    next_id: AtomicU64,
    queue: Arc<Queue>,
    dir: PathBuf,
}

//file helpers
fn valid_package(name: &str) -> bool {
    !name.is_empty() && name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_')
}

fn purge_stale(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let stale = entry
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.elapsed().ok())
            .is_some_and(|age| age > CACHE_TTL);
        if !stale {
            continue;
        }
        let path = entry.path();
        let _ = if path.is_dir() {
            std::fs::remove_dir_all(&path)
        } else {
            std::fs::remove_file(&path)
        };
    }
}

//streaming
fn pump(mut reader: impl Read + Send + 'static) -> Receiver<std::io::Result<Vec<u8>>> {
    let (tx, rx) = sync_channel(BACKLOG);
    std::thread::spawn(move || loop {
        let mut buf = vec![0u8; CHUNK];
        match reader.read(&mut buf) {
            Ok(0) => return,
            Ok(n) => {
                buf.truncate(n);
                if tx.send(Ok(buf)).is_err() {
                    return;
                }
            }
            Err(e) => {
                let _ = tx.send(Err(e));
                return;
            }
        }
    });
    rx
}

fn stream_to_file(job: &Job, http: &Http, url: &str, path: &Path, args: &StartArgs) -> Result<()> {
    let resp = http
        .agent()
        .get(url)
        .header("Accept-Encoding", "identity")
        .config()
        .timeout_global(Some(BACKSTOP))
        .build()
        .call()?;
    let status = resp.status().as_u16();
    if !(200..300).contains(&status) {
        return Err(EngineError::new(format!("download_http_{status}")));
    }
    let cap = args.apk_size as u64;
    let body = resp.into_body();
    job.total.store(body.content_length().unwrap_or(cap), Ordering::Relaxed);
    let chunks = pump(body.into_with_config().limit(u64::MAX).reader());

    let mut hasher = Sha256::new();
    let mut writer = BufWriter::with_capacity(4 * CHUNK, File::create(path)?);
    let mut received: u64 = 0;
    let mut last_data = Instant::now();

    loop {
        while job.paused.load(Ordering::Relaxed) && !job.cancelled.load(Ordering::Relaxed) {
            std::thread::sleep(Duration::from_millis(50));
            last_data = Instant::now();
        }
        if job.cancelled.load(Ordering::Relaxed) {
            return Err(EngineError::new(CANCELLED));
        }
        match chunks.recv_timeout(POLL) {
            Ok(Ok(chunk)) => {
                last_data = Instant::now();
                writer.write_all(&chunk)?;
                hasher.update(&chunk);
                received += chunk.len() as u64;
                job.received.store(received, Ordering::Relaxed);
                if received > cap {
                    return Err(EngineError::new("apk_size_mismatch"));
                }
            }
            Ok(Err(e)) => return Err(e.into()),
            Err(RecvTimeoutError::Timeout) => {
                if last_data.elapsed() > STALL {
                    return Err(EngineError::new("download_stalled"));
                }
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }
    writer.flush()?;
    drop(writer);

    if job.cancelled.load(Ordering::Relaxed) {
        return Err(EngineError::new(CANCELLED));
    }
    if received != cap {
        return Err(EngineError::new("apk_size_mismatch"));
    }
    let expected = args.sha256.as_deref().map(str::trim).filter(|h| !h.is_empty());
    if let Some(expected) = expected {
        let actual: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();
        if !actual.eq_ignore_ascii_case(expected) {
            return Err(EngineError::new("apk_hash_mismatch"));
        }
    }
    Ok(())
}

fn execute(job: &Job, http: &Http, dir: &Path, args: &StartArgs) -> Result<PathBuf> {
    if job.cancelled.load(Ordering::Relaxed) {
        return Err(EngineError::new(CANCELLED));
    }
    let url = http.download_url(&args.package_name, args.version_code)?;
    std::fs::create_dir_all(dir)?;
    purge_stale(dir);
    let path = dir.join(format!("{}-{}.apk", args.package_name, args.version_code));
    match stream_to_file(job, http, &url, &path, args) {
        Ok(()) => Ok(path),
        Err(e) => {
            let _ = std::fs::remove_file(&path);
            Err(e)
        }
    }
}

//pub api
impl Downloads {
    pub fn new(data_dir: &Path) -> Self {
        let dir = data_dir.join("install_cache");
        purge_stale(&dir);
        Self {
            jobs: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            queue: Arc::new(Queue { line: Mutex::new(VecDeque::new()), changed: Condvar::new() }),
            dir,
        }
    }

    pub fn start(&self, http: &Http, args: StartArgs) -> Result<u64> {
        if !valid_package(&args.package_name) {
            return Err(EngineError::new("invalid_package_name"));
        }
        if args.apk_size <= 0 {
            return Err(EngineError::new("invalid_apk_size"));
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let job = Arc::new(Job {
            state: AtomicU8::new(QUEUED),
            received: AtomicU64::new(0),
            total: AtomicU64::new(0),
            paused: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
            error: Mutex::new(None),
            path: Mutex::new(None),
        });
        lock(&self.jobs).insert(id, job.clone());
        lock(&self.queue.line).push_back(id);

        let queue = self.queue.clone();
        let http = http.clone();
        let dir = self.dir.clone();
        let spawned = std::thread::Builder::new().spawn(move || {
            {
                let mut line = lock(&queue.line);
                while line.front() != Some(&id) {
                    line = queue.changed.wait(line).unwrap_or_else(|e| e.into_inner());
                }
            }
            let _guard = TurnGuard { queue: &queue };
            job.state.store(RUNNING, Ordering::Release);
            let outcome = catch_unwind(AssertUnwindSafe(|| execute(&job, &http, &dir, &args)))
                .unwrap_or_else(|_| Err(EngineError::new("download_panic")));
            match outcome {
                Ok(path) => {
                    *lock(&job.path) = Some(path.to_string_lossy().into_owned());
                    job.state.store(DONE, Ordering::Release);
                }
                Err(e) => {
                    *lock(&job.error) = Some(e.0);
                    job.state.store(FAILED, Ordering::Release);
                }
            }
        });
        if spawned.is_err() {
            lock(&self.jobs).remove(&id);
            lock(&self.queue.line).retain(|&queued| queued != id);
            self.queue.changed.notify_all();
            return Err(EngineError::new("thread_spawn_failed"));
        }
        Ok(id)
    }

    fn resolve(&self, id: Option<u64>) -> Option<Arc<Job>> {
        let id = id.or_else(|| lock(&self.queue.line).front().copied())?;
        lock(&self.jobs).get(&id).cloned()
    }

    pub fn status(&self, id: u64) -> Result<Status> {
        let job = lock(&self.jobs)
            .get(&id)
            .cloned()
            .ok_or_else(|| EngineError::new("unknown_job"))?;
        let state = job.state.load(Ordering::Acquire);
        let cancelled = job.cancelled.load(Ordering::Relaxed);
        let (label, error) = match state {
            DONE => ("done", None),
            FAILED => ("failed", lock(&job.error).clone()),
            _ if cancelled => ("failed", Some(CANCELLED.to_owned())),
            RUNNING => ("running", None),
            _ => ("queued", None),
        };
        if label == "done" || label == "failed" {
            lock(&self.jobs).remove(&id);
        }
        let path = lock(&job.path).clone();
        Ok(Status {
            state: label,
            received: job.received.load(Ordering::Relaxed),
            total: job.total.load(Ordering::Relaxed),
            error,
            path,
        })
    }

    pub fn pause(&self, id: Option<u64>) -> bool {
        self.resolve(id)
            .map(|job| job.paused.store(true, Ordering::Relaxed))
            .is_some()
    }

    pub fn resume(&self, id: Option<u64>) -> bool {
        self.resolve(id)
            .map(|job| job.paused.store(false, Ordering::Relaxed))
            .is_some()
    }

    pub fn cancel(&self, id: Option<u64>) -> bool {
        self.resolve(id)
            .map(|job| {
                job.cancelled.store(true, Ordering::Relaxed);
                job.paused.store(false, Ordering::Relaxed);
            })
            .is_some()
    }
}