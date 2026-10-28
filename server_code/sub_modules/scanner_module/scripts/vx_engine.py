import ctypes
import json
import os

VXTITANIUM_LIB_PATH  = os.getenv("VXTITANIUM_LIB_PATH",  "/opt/vx-titanium/lib/libcolourswift_av.so")
VXTITANIUM_DEFS_PATH = os.getenv("VXTITANIUM_DEFS_PATH",  "/opt/vx-titanium/defs/defs.cs")
VXTITANIUM_DATA_DIR  = os.getenv("VXTITANIUM_DATA_DIR",  "/var/lib/vx-titanium")
TFLITE_LIB_PATH      = os.getenv("TFLITE_LIB_PATH", os.path.join(os.path.dirname(VXTITANIUM_LIB_PATH), "libtensorflowlite_c.so"))

ENGINE_NAME = "vx-titanium"
DETECTED = "Detected"
HASH_LABELS = {"HashMatch", "Cloud.Hash", "Cloud.Molecule"}
CLOUD_FINISH_TIMEOUT_MS = int(os.getenv("VXTITANIUM_CLOUD_TIMEOUT_MS", "30000"))

_lib: ctypes.CDLL | None = None
_version: str = "unknown"
_init_error: str | None = None


def _take_string(lib: ctypes.CDLL, ptr: int | None) -> str | None:
    if ptr is None:
        return None
    try:
        return ctypes.cast(ptr, ctypes.c_char_p).value.decode("utf-8", errors="replace")
    finally:
        lib.vx_free_string(ptr)


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

        lib.vx_set_data_dir.restype   = None
        lib.vx_set_data_dir.argtypes  = [ctypes.c_char_p]

        lib.vx_set_cloud.restype      = None
        lib.vx_set_cloud.argtypes     = [ctypes.c_int]

        lib.vx_cloud_begin.restype    = ctypes.c_int
        lib.vx_cloud_begin.argtypes   = []

        lib.vx_cloud_finish.restype   = ctypes.c_void_p
        lib.vx_cloud_finish.argtypes  = [ctypes.c_int]

        version_str = _take_string(lib, lib.vx_version())
        if version_str is not None:
            _version = version_str

        os.makedirs(VXTITANIUM_DATA_DIR, exist_ok=True)
        lib.vx_set_data_dir(VXTITANIUM_DATA_DIR.encode())

        rc = lib.vx_init(VXTITANIUM_DEFS_PATH.encode(), None)
        if rc != 0:
            raise RuntimeError(f"vx_init returned {rc} (defs={VXTITANIUM_DEFS_PATH!r})")

        lib.vx_set_cloud(1)

        _lib = lib
        return lib

    except Exception as exc:
        _init_error = str(exc)
        raise


def version() -> str:
    return _version


def _failure(error: str) -> dict:
    return {
        "verdict":    "unknown",
        "engine":     ENGINE_NAME,
        "version":    _version,
        "detections": [],
        "error":      error,
    }


def _label(name: str) -> str:
    return DETECTED if name in HASH_LABELS else name


def scan(apk_path: str) -> dict:
    lib = _load()

    session = lib.vx_cloud_begin() == 0
    try:
        raw_json = _take_string(lib, lib.vx_scan_file(apk_path.encode()))
    finally:
        raw_cloud = _take_string(lib, lib.vx_cloud_finish(CLOUD_FINISH_TIMEOUT_MS)) if session else None

    if raw_json is None:
        return _failure("vx_scan_file returned null")

    try:
        data = json.loads(raw_json)
    except Exception as exc:
        return _failure(f"json parse failed: {exc}")

    detections = [
        {"file": file_path, "name": _label(name)}
        for file_path, names in data.get("hits", {}).items()
        for name in names
    ]

    if raw_cloud is not None:
        try:
            detections.extend(
                {"file": r["path"], "name": _label(r["label"])}
                for r in json.loads(raw_cloud).get("results", [])
            )
        except Exception:
            pass

    return {
        "verdict":    "malware" if detections else "clean",
        "engine":     ENGINE_NAME,
        "version":    _version,
        "detections": detections,
    }