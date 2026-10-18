#![allow(clippy::missing_safety_doc, clippy::module_inception)]
mod data;
mod engine;
mod jni_bridge;
mod modules;
mod net;
mod notice;

use engine::engine::init;
use engine::resolver::{call, EngineError, Result};
use std::any::Any;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

//ffi helpers
unsafe fn read(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

fn panic_error(payload: Box<dyn Any + Send>) -> EngineError {
    let detail = payload
        .downcast_ref::<&str>()
        .map(|s| (*s).to_owned())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_default();
    EngineError::new(format!("engine_panic_{detail}"))
}

fn envelope(result: Result<String>) -> String {
    match result {
        Ok(mut value) => {
            value.reserve_exact(8);
            value.insert_str(0, r#"{"ok":"#);
            value.push('}');
            value
        }
        Err(e) => serde_json::json!({ "err": e.0 }).to_string(),
    }
}

fn into_c(text: String) -> *mut c_char {
    CString::new(text).unwrap_or_default().into_raw()
}

//exported c api
#[no_mangle]
pub unsafe extern "C" fn sh_init(base_url: *const c_char, data_dir: *const c_char) -> i32 {
    let base = read(base_url);
    let dir = read(data_dir);
    match catch_unwind(AssertUnwindSafe(|| init(&base, &dir))) {
        Ok(Ok(())) => 0,
        _ => 1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn sh_call(method: *const c_char, args: *const c_char) -> *mut c_char {
    let method = read(method);
    let args = read(args);
    let result = catch_unwind(AssertUnwindSafe(|| call(&method, &args)))
        .unwrap_or_else(|payload| Err(panic_error(payload)));
    into_c(envelope(result))
}

#[no_mangle]
pub unsafe extern "C" fn sh_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
