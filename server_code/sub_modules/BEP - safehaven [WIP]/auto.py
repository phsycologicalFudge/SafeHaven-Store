import sys
import os
import json
import random
import shutil
import subprocess
import urllib.request
import urllib.error
import argparse

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
BEP_ENV     = os.path.join(SCRIPT_DIR, "BEP_env")
BINARY_DIR  = os.path.join(BEP_ENV, "binary")
SOURCE_DIR  = os.path.join(BEP_ENV, "source")
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")


def log(msg):
    print(f"[auto] {msg}", flush=True)


def die(msg):
    print(f"[error] {msg}", flush=True)
    sys.exit(1)


def http_get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "BEP-auto/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def download_file(url, dest_path):
    req = urllib.request.Request(url, headers={"User-Agent": "BEP-auto/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        with open(dest_path, "wb") as f:
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                f.write(chunk)


def clear_dir(path):
    for name in os.listdir(path):
        fp = os.path.join(path, name)
        if os.path.isfile(fp):
            os.remove(fp)


def fetch_index(store_url):
    url = f"{store_url.rstrip('/')}/store/index.json"
    log(f"fetching index from {url}")
    return http_get_json(url)


def get_download_url(store_url, package_name, version_code):
    url = f"{store_url.rstrip('/')}/store/apps/{package_name}/download/{version_code}"
    data = http_get_json(url)
    return data["url"]


def run_bep(repo_url, verbose):
    cmd = [sys.executable, os.path.join(SCRIPT_DIR, "main.py"), repo_url]
    if verbose:
        cmd.append("--verbose")
    return subprocess.run(cmd).returncode


def main():
    parser = argparse.ArgumentParser(prog="bep-auto")
    parser.add_argument("--store-url", default=os.getenv("STORE_URL", ""), help="SafeHaven store base URL")
    parser.add_argument("--count", type=int, default=1, help="number of apps to test (default 1)")
    parser.add_argument("--all", action="store_true", help="run all eligible apps")
    parser.add_argument("-v", "--verbose", action="store_true", help="show full build output")
    args = parser.parse_args()

    store_url = args.store_url.rstrip("/")
    if not store_url:
        die("--store-url is required (or set STORE_URL env var)")

    os.makedirs(BINARY_DIR, exist_ok=True)
    os.makedirs(SOURCE_DIR, exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    index = fetch_index(store_url)

    eligible = [
        app for app in index.get("apps", [])
        if app.get("versions")
        and app.get("repoUrl", "").startswith("https://github.com/")
    ]

    if not eligible:
        die("no eligible apps found in index (need at least one version + GitHub repo)")

    targets = eligible if args.all else random.sample(eligible, min(args.count, len(eligible)))
    total   = len(targets)
    log(f"selected {total} app(s) from {len(eligible)} eligible\n")

    passed = 0
    failed = 0
    errors = []

    for i, app in enumerate(targets, 1):
        pkg          = app["packageName"]
        repo_url     = app["repoUrl"]
        version      = app["versions"][0]
        version_code = version["versionCode"]
        version_name = version.get("versionName", str(version_code))

        print(f"[{i}/{total}]  {pkg}  v{version_name}", flush=True)

        clear_dir(BINARY_DIR)
        clear_dir(SOURCE_DIR)

        apk_name = f"{pkg}.apk"
        apk_path = os.path.join(BINARY_DIR, apk_name)

        try:
            dl_url = get_download_url(store_url, pkg, version_code)
            download_file(dl_url, apk_path)
        except Exception as e:
            print(f"  [error] APK download failed: {e}", flush=True)
            errors.append({"packageName": pkg, "error": f"download_failed: {e}"})
            failed += 1
            continue

        rc = run_bep(repo_url, args.verbose)

        stem        = os.path.splitext(apk_name)[0]
        report_src  = os.path.join(BEP_ENV, f"{stem}_bep_report.json")
        report_dest = os.path.join(RESULTS_DIR, f"{pkg}_{version_code}_bep_report.json")

        if os.path.exists(report_src):
            shutil.move(report_src, report_dest)
            with open(report_dest, encoding="utf-8") as f:
                report = json.load(f)
            verdict    = report.get("verdict", "UNKNOWN")
            confidence = report.get("confidence", 0)
            if verdict in ("LIKELY_CLEAN", "SUSPICIOUS"):
                passed += 1
            else:
                failed += 1
            print(f"  → {verdict}  ({confidence:.4f})  {os.path.basename(report_dest)}\n", flush=True)
        else:
            print(f"  [warn] no report found (rc={rc}) — run with --verbose for details\n", flush=True)
            errors.append({"packageName": pkg, "error": "no_report"})
            if rc != 0:
                failed += 1

        clear_dir(BINARY_DIR)
        clear_dir(SOURCE_DIR)

    print(f"done   passed={passed}  failed={failed}  errors={len(errors)}", flush=True)
    if errors:
        for e in errors:
            print(f"  {e['packageName']}: {e['error']}", flush=True)


if __name__ == "__main__":
    main()
