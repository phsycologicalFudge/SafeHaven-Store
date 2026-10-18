use crate::engine::engine::init;
use crate::engine::resolver::call;
use crate::{envelope, panic_error};
use jni::objects::{JClass, JString};
use jni::sys::{jint, jstring};
use jni::JNIEnv;
use std::panic::{catch_unwind, AssertUnwindSafe};

fn text(env: &mut JNIEnv, value: &JString) -> String {
    env.get_string(value).map(String::from).unwrap_or_default()
}

#[no_mangle]
pub extern "system" fn Java_com_colourswift_safehaven_EngineNative_init(
    mut env: JNIEnv,
    _class: JClass,
    base_url: JString,
    data_dir: JString,
) -> jint {
    let base = text(&mut env, &base_url);
    let dir = text(&mut env, &data_dir);
    match catch_unwind(AssertUnwindSafe(|| init(&base, &dir))) {
        Ok(Ok(())) => 0,
        _ => 1,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_colourswift_safehaven_EngineNative_call(
    mut env: JNIEnv,
    _class: JClass,
    method: JString,
    args: JString,
) -> jstring {
    let method = text(&mut env, &method);
    let args = text(&mut env, &args);
    let result = catch_unwind(AssertUnwindSafe(|| call(&method, &args)))
        .unwrap_or_else(|payload| Err(panic_error(payload)));
    env.new_string(envelope(result)).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}
