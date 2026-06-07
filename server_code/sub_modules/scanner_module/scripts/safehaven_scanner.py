import asyncio
import base64
import hashlib
import os
import re
import struct
import sys
import time
import zipfile
import httpx
import subprocess
import tempfile
from typing import Any
from fastapi import FastAPI

CS_API_URL       = os.getenv("CS_API_URL", "https://api.colourswift.com").rstrip("/")
VPS_AUTH_SECRET  = os.getenv("VPS_AUTH_SECRET", "").strip()
POLL_INTERVAL    = int(os.getenv("POLL_INTERVAL", "30"))
HASH_API_URL     = "https://efkou1u21ooih2hko.colourswift.com/check_batch"
HASH_API_KEY     = "23JVO3ojo23oO3O423rrTR"
HASH_TIMEOUT     = 8.0
DOWNLOAD_TIMEOUT = 60.0
RESCAN_COOLDOWN  = 7 * 86400
RESCAN_BATCH     = 10
RESCAN_IDLE      = 30
FORCE_RESCAN     = os.getenv("FORCE_RESCAN", "").strip().lower() in ("1", "true", "yes") or "--force-rescan" in sys.argv
_rescan_pkg_idx  = sys.argv.index("--rescan-pkg") if "--rescan-pkg" in sys.argv else -1
RESCAN_PKG       = sys.argv[_rescan_pkg_idx + 1].strip() if _rescan_pkg_idx != -1 and _rescan_pkg_idx + 1 < len(sys.argv) else ""
APKSIGNER_BIN    = os.getenv("APKSIGNER_BIN", "apksigner").strip()
AAPT2_BIN        = os.getenv("AAPT2_BIN", "aapt2").strip()

app = FastAPI(title="SafeHaven Scanner")

_rescan_cache: dict[str, int] = {}
_force_rescan_done: set[str] = set()

try:
    import engine as _engine_mod
    if _engine_mod.is_available():
        print(f"[scanner] engine loaded: {_engine_mod._backend.ENGINE_NAME} v{_engine_mod._backend.version()}")
    else:
        err = _engine_mod.load_error()
        print(f"[scanner] engine not available{f': {err}' if err else ' (ENGINE_ENABLED=0)'}")
except Exception as _e:
    _engine_mod = None
    print(f"[scanner] engine.py import failed: {_e}")


def _parse_lp(data: bytes, offset: int) -> tuple[bytes, int]:
    if offset + 4 > len(data):
        raise ValueError("truncated length prefix")
    length = struct.unpack_from("<I", data, offset)[0]
    end = offset + 4 + length
    if end > len(data):
        raise ValueError("length prefix overruns buffer")
    return data[offset + 4:end], end


def extract_apk_manifest_info(apk_bytes: bytes) -> dict[str, Any]:
    apk_path = ""
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".apk") as tmp:
            tmp.write(apk_bytes)
            apk_path = tmp.name

        result = subprocess.run(
            [AAPT2_BIN, "dump", "badging", apk_path],
            capture_output=True,
            text=True,
            timeout=20,
        )

        if result.returncode != 0:
            return {}

        for line in result.stdout.splitlines():
            if not line.startswith("package:"):
                continue
            info: dict[str, Any] = {}
            m = re.search(r"name='([^']+)'", line)
            if m:
                info["packageName"] = m.group(1)
            m = re.search(r"versionCode='([^']+)'", line)
            if m:
                try:
                    info["versionCode"] = int(m.group(1))
                except ValueError:
                    pass
            m = re.search(r"versionName='([^']+)'", line)
            if m:
                info["versionName"] = m.group(1)
            return info

        return {}

    except Exception:
        return {}

    finally:
        if apk_path:
            try:
                os.remove(apk_path)
            except Exception:
                pass


_RASTER_EXTS: dict[str, str] = {
    ".png":  "image/png",
    ".webp": "image/webp",
    ".jpg":  "image/jpeg",
    ".jpeg": "image/jpeg",
}

_MIPMAP_DPI_ORDER = [
    "xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", "anydpi", "nodpi", "",
]


def _dpi_rank(zip_path: str) -> int:
    lower = zip_path.lower()
    for rank, label in enumerate(_MIPMAP_DPI_ORDER):
        if label and f"-{label}" in lower:
            return rank
    return len(_MIPMAP_DPI_ORDER)


def _resource_basename(zip_path: str) -> str:
    name = zip_path.rsplit("/", 1)[-1]
    return name.rsplit(".", 1)[0].lower()


def _icon_payload_from_zip_path(apk_zip: zipfile.ZipFile, zip_path: str) -> dict[str, str] | None:
    lower = zip_path.lower()
    ext = next((e for e in _RASTER_EXTS if lower.endswith(e)), None)
    if ext is None:
        return None

    try:
        icon_bytes = apk_zip.read(zip_path)
    except KeyError:
        return None

    if not icon_bytes or len(icon_bytes) > 2 * 1024 * 1024:
        return None

    return {
        "iconBase64":      base64.b64encode(icon_bytes).decode("ascii"),
        "iconContentType": _RASTER_EXTS[ext],
    }


def _is_raster_icon_path(zip_path: str) -> bool:
    lower = zip_path.lower()
    if not any(lower.endswith(ext) for ext in _RASTER_EXTS):
        return False

    allowed_roots = (
        "res/mipmap",
        "res/drawable",
        "res/raw",
        "assets/",
    )

    if lower.startswith(allowed_roots):
        return True

    filename = lower.rsplit("/", 1)[-1]
    return filename in (
        "play_store.png",
        "play_store.webp",
        "store_icon.png",
        "store_icon.webp",
        "listing_icon.png",
        "listing_icon.webp",
        "icon.png",
        "icon.webp",
    )


def _icon_candidate_score(zip_path: str) -> tuple[int, int, str]:
    lower = zip_path.lower()
    base = _resource_basename(zip_path)
    filename = lower.rsplit("/", 1)[-1]

    if base in ("ic_launcher", "launcher_icon", "app_icon"):
        priority = 0
    elif base in ("ic_launcher_round", "launcher_round"):
        priority = 1
    elif base in ("ic_launcher_foreground", "launcher_foreground"):
        priority = 2
    elif base in ("ic_launcher_monochrome", "launcher_monochrome"):
        priority = 3
    elif filename in (
        "play_store.png",
        "play_store.webp",
        "store_icon.png",
        "store_icon.webp",
        "listing_icon.png",
        "listing_icon.webp",
        "feature_graphic.png",
        "feature_graphic.webp",
    ):
        priority = 4
    elif "launcher" in base:
        priority = 5
    elif "logo" in base:
        priority = 6
    elif "icon" in base:
        priority = 7
    else:
        priority = 99

    return (priority, _dpi_rank(zip_path), zip_path)


def _aapt_icon_paths(stdout: str) -> list[tuple[int, str]]:
    candidates: list[tuple[int, str]] = []

    for line in stdout.splitlines():
        line = line.strip()

        m = re.match(r"application-icon-(\d+):'([^']+)'", line)
        if m:
            try:
                candidates.append((int(m.group(1)), m.group(2)))
            except ValueError:
                pass
            continue

        m = re.match(r"application-icon:'([^']+)'", line)
        if m:
            candidates.append((0, m.group(1)))
            continue

        m = re.match(r"application:'[^']*'.*icon='([^']+)'", line)
        if m:
            candidates.append((0, m.group(1)))

    return sorted(candidates, key=lambda x: x[0])


def extract_apk_icon(apk_bytes: bytes) -> dict[str, str] | None:
    apk_path = ""
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".apk") as tmp:
            tmp.write(apk_bytes)
            apk_path = tmp.name

        result = subprocess.run(
            [AAPT2_BIN, "dump", "badging", apk_path],
            capture_output=True,
            text=True,
            timeout=20,
        )

        if result.returncode != 0:
            return None

        candidates = _aapt_icon_paths(result.stdout)
        if not candidates:
            return None

        try:
            with zipfile.ZipFile(apk_path, "r") as apk_zip:
                for _, icon_path in candidates:
                    payload = _icon_payload_from_zip_path(apk_zip, icon_path)
                    if payload:
                        return payload
        except Exception:
            pass

        return None

    except Exception:
        return None

    finally:
        if apk_path:
            try:
                os.remove(apk_path)
            except Exception:
                pass


def extract_best_signing_cert_hash(apk_bytes: bytes) -> str | None:
    apk_path = ""
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".apk") as tmp:
            tmp.write(apk_bytes)
            apk_path = tmp.name

        result = subprocess.run(
            [APKSIGNER_BIN, "verify", "--print-certs", apk_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        for line in result.stdout.splitlines():
            if "certificate SHA-256 digest:" in line:
                parts = line.split(":", 1)
                if len(parts) == 2:
                    return parts[1].strip().lower()

        return None
    except Exception as exc:
        print(f"[scanner] apksigner error: {exc}")
        return None
    finally:
        if apk_path and os.path.exists(apk_path):
            os.remove(apk_path)


async def download_apk(url: str) -> bytes:
    async with httpx.AsyncClient(timeout=DOWNLOAD_TIMEOUT) as client:
        resp = await client.get(url, follow_redirects=True)
        resp.raise_for_status()
        return resp.content


async def _check_hashes_remote(hashes: list[str]) -> dict:
    async with httpx.AsyncClient(timeout=HASH_TIMEOUT) as client:
        resp = await client.post(
            HASH_API_URL,
            json=hashes,
            headers={"x-cs-key": HASH_API_KEY}
        )
        resp.raise_for_status()
        data = resp.json()
        found = data.get("found", [])
        return {"verdict": "known_malware" if found else "unknown", "matches": found}


async def _check_hashes_local(hashes: list[str]) -> dict:
    async with httpx.AsyncClient(timeout=HASH_TIMEOUT) as client:
        resp = await client.post(
            "http://127.0.0.1:8081/check_batch",
            json=hashes
        )
        resp.raise_for_status()
        data = resp.json()
        found = data.get("found", [])
        return {"verdict": "known_malware" if found else "unknown", "matches": found}


async def check_hashes(hashes: list[str]) -> dict:
    try:
        return await _check_hashes_remote(hashes)
    except Exception as exc:
        print(f"[scanner] remote hash check failed: {exc}, falling back to local")
        try:
            return await _check_hashes_local(hashes)
        except Exception as local_exc:
            print(f"[scanner] local hash check failed: {local_exc}")
            return {"verdict": "unknown", "matches": []}


async def run_engine_scan(apk_bytes: bytes) -> dict[str, Any] | None:
    if _engine_mod is None or not _engine_mod.is_available():
        return None

    apk_path = ""
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".apk") as tmp:
            tmp.write(apk_bytes)
            apk_path = tmp.name
            
        result = await asyncio.to_thread(_engine_mod.scan, apk_path)
        return result
    except Exception as exc:
        print(f"[scanner] engine scan error: {exc}")
        return None
    finally:
        if apk_path and os.path.exists(apk_path):
            os.remove(apk_path)


async def fetch_pending_scans() -> list[dict]:
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{CS_API_URL}/internal/store/pending-scans",
            headers={"x-vps-auth": VPS_AUTH_SECRET}
        )
        resp.raise_for_status()
        return resp.json().get("submissions", [])


async def post_scan_result(submission_id: str, result: dict) -> None:
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            f"{CS_API_URL}/internal/store/scan-result",
            json={"submissionId": submission_id, **result},
            headers={"x-vps-auth": VPS_AUTH_SECRET}
        )
        resp.raise_for_status()


async def fetch_rescan_targets() -> list[dict]:
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{CS_API_URL}/internal/store/rescan-targets",
            headers={"x-vps-auth": VPS_AUTH_SECRET}
        )
        resp.raise_for_status()
        return resp.json().get("targets", [])


async def post_rescan_result(result: dict) -> None:
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            f"{CS_API_URL}/internal/store/rescan-result",
            json=result,
            headers={"x-vps-auth": VPS_AUTH_SECRET}
        )
        resp.raise_for_status()


async def process_submission(submission: dict) -> None:
    submission_id    = submission.get("id", "").strip()
    download_url     = submission.get("downloadUrl", "").strip()
    package_name     = submission.get("packageName", "").strip()
    version_code        = submission.get("version_code", "")
    auto_tracked        = bool(submission.get("autoTracked", False))
    stored_signing_hash = (submission.get("storedSigningKeyHash") or "").strip().lower() or None

    if not submission_id or not download_url:
        print(f"[scanner] skipping submission with missing id or downloadUrl: {submission_id}")
        return

    print(f"[scanner] processing {package_name}@{version_code} ({submission_id}) auto_tracked={auto_tracked}")

    try:
        apk_bytes = await download_apk(download_url)
    except Exception as exc:
        print(f"[scanner] download failed for {submission_id}: {exc}")
        await post_scan_result(submission_id, {
            "passed":    False,
            "detail":    {"error": "download_failed", "note": str(exc)},
            "scannedAt": int(time.time()),
        })
        return

    sha256      = hashlib.sha256(apk_bytes).hexdigest()
    apk_size    = len(apk_bytes)
    signing_key = extract_best_signing_cert_hash(apk_bytes)
    manifest    = extract_apk_manifest_info(apk_bytes)
    icon         = extract_apk_icon(apk_bytes)
    scanned_at  = int(time.time())

    print(f"[scanner] sha256={sha256} size={apk_size} signingKey={signing_key} manifest={manifest} for {submission_id}")

    if auto_tracked and stored_signing_hash and signing_key:
        if signing_key != stored_signing_hash:
            print(f"[scanner] signing mismatch for {submission_id}: stored={stored_signing_hash} got={signing_key}")
            await post_scan_result(submission_id, {
                "passed":         False,
                "detail":         {
                    "verdict":         "signing_key_changed",
                    "storedKeyHash":   stored_signing_hash,
                    "observedKeyHash": signing_key,
                    "matches":         [],
                },
                "apkSha256":      sha256,
                "apkSize":        apk_size,
                "scannedAt":      scanned_at,
                "signingKeyHash": signing_key,
            })
            return

    hash_result    = await check_hashes([sha256])
    engine_result  = await run_engine_scan(apk_bytes)

    hash_verdict   = hash_result.get("verdict", "unknown")
    engine_verdict = (engine_result or {}).get("verdict")

    passed = hash_verdict != "known_malware" and engine_verdict != "malware"

    print(f"[scanner] hashVerdict={hash_verdict} engineVerdict={engine_verdict} passed={passed} for {submission_id}")

    payload: dict[str, Any] = {
        "passed":    passed,
        "detail":    hash_result,
        "apkSha256": sha256,
        "apkSize":   apk_size,
        "scannedAt": scanned_at,
    }
    if engine_result is not None:
        payload["engineResult"] = engine_result
    if signing_key:
        payload["signingKeyHash"] = signing_key
    if manifest.get("packageName"):
        payload["packageName"] = manifest["packageName"]
    if manifest.get("versionCode") is not None:
        payload["manifestVersionCode"] = manifest["versionCode"]
    if manifest.get("versionName"):
        payload["manifestVersionName"] = manifest["versionName"]
    if icon:
        payload["iconBase64"] = icon["iconBase64"]
        payload["iconContentType"] = icon["iconContentType"]

    await post_scan_result(submission_id, payload)
    print(f"[scanner] result posted for {submission_id}")


async def process_rescan(target: dict[str, Any]) -> None:
    package_name = target.get("packageName", "")
    version_code = target.get("versionCode")
    download_url = target.get("downloadUrl", "")
    cache_key    = f"{package_name}@{version_code}"

    if not package_name or version_code is None or not download_url:
        return

    print(f"[rescan] scanning {cache_key}")

    try:
        apk_bytes = await download_apk(download_url)
    except Exception as exc:
        print(f"[rescan] download failed for {cache_key}: {exc}")
        return

    sha256      = hashlib.sha256(apk_bytes).hexdigest()
    apk_size    = len(apk_bytes)
    signing_key = extract_best_signing_cert_hash(apk_bytes)
    manifest    = extract_apk_manifest_info(apk_bytes)
    icon         = extract_apk_icon(apk_bytes)
    scanned_at  = int(time.time())

    hash_result    = await check_hashes([sha256])
    engine_result  = await run_engine_scan(apk_bytes)

    hash_verdict   = hash_result.get("verdict", "unknown")
    engine_verdict = (engine_result or {}).get("verdict")

    passed = hash_verdict != "known_malware" and engine_verdict != "malware"

    print(f"[rescan] hashVerdict={hash_verdict} engineVerdict={engine_verdict} passed={passed} for {cache_key}")

    payload: dict[str, Any] = {
        "packageName": package_name,
        "versionCode": version_code,
        "passed":      passed,
        "detail":      hash_result,
        "apkSha256":   sha256,
        "apkSize":     apk_size,
        "scannedAt":   scanned_at,
    }
    if engine_result is not None:
        payload["engineResult"] = engine_result
    if signing_key:
        payload["signingKeyHash"] = signing_key
    if manifest.get("packageName"):
        payload["manifestPackageName"] = manifest["packageName"]
    if manifest.get("versionCode") is not None:
        payload["manifestVersionCode"] = manifest["versionCode"]
    if manifest.get("versionName"):
        payload["manifestVersionName"] = manifest["versionName"]
    if icon:
        payload["iconBase64"] = icon["iconBase64"]
        payload["iconContentType"] = icon["iconContentType"]

    try:
        await post_rescan_result(payload)
        _rescan_cache[cache_key] = scanned_at
        _force_rescan_done.add(cache_key)
        print(f"[rescan] result posted for {cache_key}")
    except Exception as exc:
        print(f"[rescan] post failed for {cache_key}: {exc}")


async def poll_loop() -> None:
    print(f"[scanner] poll loop started — interval={POLL_INTERVAL}s")
    while True:
        try:
            submissions = await fetch_pending_scans()
            if submissions:
                print(f"[scanner] {len(submissions)} pending scan(s)")
                for submission in submissions:
                    try:
                        await process_submission(submission)
                    except Exception as exc:
                        print(f"[scanner] error processing {submission.get('id')}: {exc}")
        except Exception as exc:
            print(f"[scanner] poll error: {exc}")

        await asyncio.sleep(POLL_INTERVAL)


async def rescan_loop() -> None:
    print(f"[rescan] rescan loop started — cooldown={RESCAN_COOLDOWN}s batch={RESCAN_BATCH} idle={RESCAN_IDLE}s")
    while True:
        try:
            targets = await fetch_rescan_targets()
            now     = int(time.time())

            candidates = []
            for t in targets:
                key = f"{t.get('packageName')}@{t.get('versionCode')}"

                if FORCE_RESCAN and key not in _force_rescan_done:
                    candidates.append((0, t))
                    continue

                last_scanned = _rescan_cache.get(key) or t.get("scannedAt") or 0
                if now - last_scanned >= RESCAN_COOLDOWN:
                    candidates.append((last_scanned, t))

            candidates.sort(key=lambda x: x[0])
            batch = [t for _, t in candidates[:RESCAN_BATCH]]

            if batch:
                print(f"[rescan] {len(batch)} target(s) due")
                for target in batch:
                    try:
                        await process_rescan(target)
                    except Exception as exc:
                        print(f"[rescan] error: {exc}")
            else:
                print("[rescan] no targets due, idling")

        except Exception as exc:
            print(f"[rescan] loop error: {exc}")

        await asyncio.sleep(RESCAN_IDLE)


async def rescan_single(package_name: str) -> None:
    print(f"[rescan-single] targeting {package_name}")
    try:
        targets = await fetch_rescan_targets()
        target = next((t for t in targets if t.get("packageName") == package_name), None)
        if not target:
            print(f"[rescan-single] no rescan target found for {package_name}")
            return
        _rescan_cache.pop(f"{package_name}@{target.get('versionCode')}", None)
        await process_rescan(target)
    except Exception as exc:
        print(f"[rescan-single] error: {exc}")


@app.on_event("startup")
async def startup() -> None:
    if not VPS_AUTH_SECRET:
        raise RuntimeError("VPS_AUTH_SECRET is not set")
    if RESCAN_PKG:
        print(f"[scanner] --rescan-pkg set: will force rescan {RESCAN_PKG} on startup")
        asyncio.create_task(rescan_single(RESCAN_PKG))
    asyncio.create_task(poll_loop())
    asyncio.create_task(rescan_loop())


MONITORED_SERVICES = [
    "safehaven-hash",
    "safehaven-defs",
    "safehaven-scanner",
    "safehaven-fdroid",
]


def _check_services() -> dict[str, str]:
    statuses: dict[str, str] = {}
    for svc in MONITORED_SERVICES:
        try:
            result = subprocess.run(
                ["systemctl", "is-active", svc],
                capture_output=True,
                text=True,
                timeout=5,
            )
            statuses[svc] = result.stdout.strip()
        except Exception as exc:
            statuses[svc] = f"error: {exc}"
    return statuses


@app.get("/health")
async def health() -> dict[str, Any]:
    engine_status: dict[str, Any] = {"available": False}
    if _engine_mod is not None:
        engine_status["available"] = _engine_mod.is_available()
        err = _engine_mod.load_error()
        if err:
            engine_status["error"] = err
        elif _engine_mod.is_available():
            engine_status["engine"] = _engine_mod._backend.ENGINE_NAME
            engine_status["version"] = _engine_mod._backend.version()

    services = await asyncio.to_thread(_check_services)

    return {
        "ok":            True,
        "hash_api_url":  HASH_API_URL,
        "api_url":       CS_API_URL,
        "poll_interval": POLL_INTERVAL,
        "rescan_cached": len(_rescan_cache),
        "force_rescan":  FORCE_RESCAN,
        "force_done":    len(_force_rescan_done),
        "engine":        engine_status,
        "services":      services,
    }