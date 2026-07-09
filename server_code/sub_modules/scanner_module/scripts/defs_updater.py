import asyncio
import json
import os
import subprocess
import urllib.request
from pathlib import Path

GITHUB_REPO     = "phsycologicalFudge/AVDatabase"
DEFS_DIR        = Path(os.getenv("DEFS_DIR", "/root/optional_engine/defs"))
VERSION_FILE    = DEFS_DIR / "version.json"
UPDATE_INTERVAL = int(os.getenv("DEFS_UPDATE_INTERVAL", str(60 * 60 * 24)))
SCANNER_SERVICE = "safehaven-scanner"

RELEASES_URL = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
ASSETS       = ["defs.cs", "version.json"]


def _current_version() -> str | None:
    try:
        with open(VERSION_FILE, "r") as f:
            return json.load(f).get("version")
    except Exception:
        return None


def _fetch_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "CS-Defs-Updater/1.0", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def _download(url: str, dest: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "CS-Defs-Updater/1.0"})
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    with urllib.request.urlopen(req, timeout=60) as resp:
        tmp.write_bytes(resp.read())
    tmp.replace(dest)


def _run_update() -> bool:
    print("[defs] checking for updates")

    release = _fetch_json(RELEASES_URL)
    latest  = release.get("tag_name", "").lstrip("v")

    if not latest:
        print("[defs] could not determine latest version")
        return False

    current = _current_version()
    print(f"[defs] current={current} latest={latest}")

    if current == latest:
        print("[defs] already up to date")
        return False

    assets = {a["name"]: a["browser_download_url"] for a in release.get("assets", [])}
    missing = [name for name in ASSETS if name not in assets]
    if missing:
        print(f"[defs] missing expected assets: {missing}")
        return False

    DEFS_DIR.mkdir(parents=True, exist_ok=True)

    for name in ASSETS:
        url  = assets[name]
        dest = DEFS_DIR / name
        print(f"[defs] downloading {name}")
        _download(url, dest)

    print(f"[defs] updated to {latest}, restarting scanner")
    subprocess.run(["systemctl", "restart", SCANNER_SERVICE], check=False)
    return True


async def _update_loop() -> None:
    print(f"[defs] updater started — interval={UPDATE_INTERVAL}s")
    while True:
        try:
            await asyncio.to_thread(_run_update)
        except Exception as exc:
            print(f"[defs] update error: {exc}")
        await asyncio.sleep(UPDATE_INTERVAL)


if __name__ == "__main__":
    asyncio.run(_update_loop())