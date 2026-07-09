import ctypes
import json
import os

VXTITANIUM_LIB_PATH  = os.getenv("VXTITANIUM_LIB_PATH",  "/opt/vx-titanium/lib/libcolourswift_av.so")
VXTITANIUM_DEFS_PATH = os.getenv("VXTITANIUM_DEFS_PATH",  "/opt/vx-titanium/defs/defs.cs")
TFLITE_LIB_PATH      = os.getenv("TFLITE_LIB_PATH", os.path.join(os.path.dirname(VXTITANIUM_LIB_PATH), "libtensorflowlite_c.so"))

ENGINE_NAME = "vx-titanium"

_lib: ctypes.CDLL | None = None
_version: str = "unknown"
_init_error: str | None = None


def _load() -> ctypes.CDLL:
    global _lib, _version, _init_error

    if _lib is not None:
        return _lib

    if _init_error is not None:
        raise RuntimeError(_init_error)

    try:
        if os.path.exists(TFLITE_LIB_PATH):
            ctypes.CDLL(TFLITE_LIB_PATH, mode=ctypes.RTLD_GLOBAL)

        lib = ctypes.CDLL(VXTITANIUM_LIB_PATH)

        lib.vx_init.restype           = ctypes.c_int
        lib.vx_init.argtypes          = [ctypes.c_char_p, ctypes.c_char_p]

        lib.vx_scan_file.restype      = ctypes.c_void_p
        lib.vx_scan_file.argtypes     = [ctypes.c_char_p]

        lib.vx_free_string.restype    = None
        lib.vx_free_string.argtypes   = [ctypes.c_void_p]

        lib.vx_version.restype        = ctypes.c_void_p
        lib.vx_version.argtypes       = []

        ver_ptr = lib.vx_version()
        if ver_ptr is not None:
            _version = ctypes.cast(ver_ptr, ctypes.c_char_p).value.decode("utf-8", errors="replace")
            lib.vx_free_string(ver_ptr)

        rc = lib.vx_init(VXTITANIUM_DEFS_PATH.encode(), None)
        if rc != 0:
            raise RuntimeError(f"vx_init returned {rc} (defs={VXTITANIUM_DEFS_PATH!r})")

        _lib = lib
        return lib

    except Exception as exc:
        _init_error = str(exc)
        raise


def version() -> str:
    return _version


def scan(apk_path: str) -> dict:
    lib = _load()

    ptr = lib.vx_scan_file(apk_path.encode())

    if ptr is None:
        return {
            "verdict":    "unknown",
            "engine":     ENGINE_NAME,
            "version":    _version,
            "detections": [],
            "error":      "vx_scan_file returned null",
        }

    try:
        raw_json = ctypes.cast(ptr, ctypes.c_char_p).value.decode("utf-8", errors="replace")
    finally:
        lib.vx_free_string(ptr)

    try:
        data = json.loads(raw_json)
    except Exception as exc:
        return {
            "verdict":    "unknown",
            "engine":     ENGINE_NAME,
            "version":    _version,
            "detections": [],
            "error":      f"json parse failed: {exc}",
        }

    hits = data.get("hits", {})
    detections = [
        {"file": file_path, "name": name}
        for file_path, names in hits.items()
        for name in names
    ]

    return {
        "verdict":    "malware" if detections else "clean",
        "engine":     ENGINE_NAME,
        "version":    _version,
        "detections": detections,
    }