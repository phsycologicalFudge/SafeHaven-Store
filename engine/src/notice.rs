#[no_mangle]
pub static SAFEHAVEN_NOTICE: &str = concat!(
    "SafeHaven Store engine v",
    env!("CARGO_PKG_VERSION"),
    " | https://github.com/phsycologicalFudge/SafeHaven-Store\n\n",
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../LICENSE"))
);