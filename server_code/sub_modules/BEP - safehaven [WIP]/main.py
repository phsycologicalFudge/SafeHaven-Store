import sys
import os
import re
import glob
import json
import stat
import subprocess
import urllib.request
import urllib.error
import time
import threading
import itertools
import argparse

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PIPELINE_DIR = os.path.join(SCRIPT_DIR, "pipeline")
BEP_ENV      = os.path.join(SCRIPT_DIR, "BEP_env")
BINARY_DIR   = os.path.join(BEP_ENV, "binary")
BUILD_ENV    = os.path.join(SCRIPT_DIR, "build_env")

AAPT2_BIN    = os.getenv("AAPT2_BIN", "aapt2").strip()
DOCKER_IMAGE = os.getenv("BEP_IMAGE", "bep-runner:latest")

VERBOSE = False

_GREEN  = "\033[92m"
_YELLOW = "\033[93m"
_RED    = "\033[91m"
_RESET  = "\033[0m"

_SPIN_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
_spin_active = threading.Event()
_spin_label  = [""]
_spin_thread = None


def _spin_worker():
    for frame in itertools.cycle(_SPIN_FRAMES):
        if not _spin_active.is_set():
            return
        print(f"\r  {frame}  {_spin_label[0]}", end="", flush=True)
        time.sleep(0.08)


def _spin_start(label):
    global _spin_thread
    _spin_label[0] = label
    _spin_active.set()
    _spin_thread = threading.Thread(target=_spin_worker, daemon=True)
    _spin_thread.start()


def _spin_update(label):
    _spin_label[0] = label


def _spin_stop(label=None, ok=True):
    global _spin_thread
    _spin_active.clear()
    if _spin_thread:
        _spin_thread.join()
        _spin_thread = None
    disp = label if label is not None else _spin_label[0]
    icon = "✓" if ok else "✗"
    print(f"\r  {icon}  {disp}" + " " * 30, flush=True)


def log(msg):
    if VERBOSE:
        print(f"[main] {msg}", flush=True)


def die(msg, verdict=None):
    if _spin_active.is_set():
        _spin_stop(ok=False)
    if verdict:
        print(f"\n[verdict] {verdict}", flush=True)
    print(f"[error] {msg}", flush=True)
    sys.exit(1)


def to_wsl_path(windows_path):
    path = os.path.abspath(windows_path)
    drive, rest = os.path.splitdrive(path)
    rest = rest.replace("\\", "/")
    return f"/mnt/{drive[0].lower()}{rest}"


def find_aapt2_in_sdk():
    sdk_root = os.getenv("ANDROID_HOME") or os.getenv("ANDROID_SDK_ROOT") or ""
    if not sdk_root:
        candidates = [
            os.path.expanduser("~/AppData/Local/Android/Sdk"),
            "C:/Users/Administrator/AppData/Local/Android/Sdk",
        ]
        for c in candidates:
            if os.path.isdir(c):
                sdk_root = c
                break
    if not sdk_root:
        return None
    exe = "aapt2.exe" if sys.platform == "win32" else "aapt2"
    pattern = os.path.join(sdk_root, "build-tools", "*", exe)
    matches = sorted(glob.glob(pattern), reverse=True)
    return matches[0] if matches else None


def ensure_aapt2():
    global AAPT2_BIN
    try:
        result = subprocess.run([AAPT2_BIN, "version"], capture_output=True)
        if result.returncode == 0:
            log(f"aapt2 found: {AAPT2_BIN}")
            return
    except FileNotFoundError:
        pass
    log("aapt2 not on PATH, searching Android SDK...")
    found = find_aapt2_in_sdk()
    if found:
        AAPT2_BIN = found
        log(f"aapt2 located: {AAPT2_BIN}")
        return
    log("aapt2 not found in SDK, trying sdkmanager...")
    import shutil
    sdkmanager = shutil.which("sdkmanager")
    if not sdkmanager:
        die("aapt2 not found and sdkmanager not on PATH")
    result = subprocess.run([sdkmanager, "build-tools;35.0.0"])
    if result.returncode != 0:
        die("sdkmanager failed to install build-tools")
    found = find_aapt2_in_sdk()
    if not found:
        die("aapt2 still not found after sdkmanager install")
    AAPT2_BIN = found
    log(f"aapt2 installed: {AAPT2_BIN}")


def get_apk_version(apk_path):
    try:
        result = subprocess.run(
            [AAPT2_BIN, "dump", "badging", apk_path],
            capture_output=True, text=True, timeout=20,
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.splitlines():
            if not line.startswith("package:"):
                continue
            m = re.search(r"versionName='([^']+)'", line)
            if m:
                return m.group(1)
        return None
    except Exception:
        return None


def github_api(path):
    url = f"https://api.github.com/{path.lstrip('/')}"
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "BEP-main"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def find_matching_tag(owner, repo, version):
    log(f"fetching tags for {owner}/{repo}...")
    tags = github_api(f"repos/{owner}/{repo}/tags")
    if not tags or not version:
        return None
    for tag in tags:
        tag_name = tag["name"]
        cleaned = tag_name.lstrip("vV").replace("-", ".").strip()
        if cleaned == version or tag_name == version or tag_name == f"v{version}":
            log(f"matched tag: {tag_name}")
            return tag_name
    log(f"no tag matched version '{version}', will use main")
    return None


def parse_repo_url(url):
    url = url.rstrip("/")
    match = re.match(r"https://github\.com/([^/]+)/([^/]+)", url)
    if not match:
        die(f"not a valid GitHub repo URL: {url}")
    return match.group(1), match.group(2)


def stream(cmd, cwd=None):
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        encoding="utf-8",
        errors="replace",
    )
    for line in proc.stdout:
        print(line, end="", flush=True)
    proc.wait()
    return proc.returncode


def _run_quiet(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, encoding="utf-8", errors="replace").returncode


def ensure_docker_daemon():
    result = subprocess.run(["wsl", "docker", "info"], capture_output=True)
    if result.returncode == 0:
        return
    log("docker daemon not running, attempting to start...")
    subprocess.run(["wsl", "-u", "root", "service", "docker", "start"], capture_output=True)
    time.sleep(3)
    result = subprocess.run(["wsl", "docker", "info"], capture_output=True)
    if result.returncode != 0:
        die(
            "docker daemon is not running and could not be started.\n"
            "Run 'sudo bash setup.sh' from WSL if you haven't already, "
            "then 'wsl --shutdown' from PowerShell and reopen WSL.",
            "DOCKER_UNAVAILABLE",
        )
    log("docker daemon started")


def ensure_docker_image():
    result = subprocess.run(
        ["wsl", "docker", "image", "inspect", DOCKER_IMAGE],
        capture_output=True,
    )
    if result.returncode == 0:
        log(f"docker image {DOCKER_IMAGE} found")
        return
    log(f"docker image {DOCKER_IMAGE} not found, building...")
    rc = stream(["wsl", "docker", "build", "-t", DOCKER_IMAGE, to_wsl_path(SCRIPT_DIR)])
    if rc != 0:
        die("docker image build failed", "BUILD_FAILED")
    log("docker image built")


def _ensure_docker_quiet():
    result = subprocess.run(["wsl", "docker", "info"], capture_output=True)
    if result.returncode != 0:
        subprocess.run(["wsl", "-u", "root", "service", "docker", "start"], capture_output=True)
        time.sleep(3)
        result = subprocess.run(["wsl", "docker", "info"], capture_output=True)
        if result.returncode != 0:
            die(
                "docker daemon is not running and could not be started.\n"
                "Run 'sudo bash setup.sh' from WSL if you haven't already, "
                "then 'wsl --shutdown' from PowerShell and reopen WSL.",
                "DOCKER_UNAVAILABLE",
            )
    result = subprocess.run(
        ["wsl", "docker", "image", "inspect", DOCKER_IMAGE],
        capture_output=True,
    )
    if result.returncode != 0:
        _spin_update("Building Docker image")
        rc = _run_quiet(["wsl", "docker", "build", "-t", DOCKER_IMAGE, to_wsl_path(SCRIPT_DIR)])
        if rc != 0:
            die("docker image build failed", "BUILD_FAILED")


def _docker_run_steps(wsl_cmd):
    _spin_start("Building APK")
    proc = subprocess.Popen(
        ["wsl", "bash", "-c", wsl_cmd],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        encoding="utf-8",
        errors="replace",
    )
    last_verdict = None
    for line in proc.stdout:
        stripped = line.strip()
        if "[runner] --- BEP ---" in stripped:
            _spin_update("Analysing APK")
        elif stripped.startswith("[verdict]"):
            last_verdict = stripped[len("[verdict]"):].strip()
    proc.wait()
    _spin_stop(ok=(proc.returncode == 0))
    return proc.returncode, last_verdict


def print_bep_summary(report):
    verdict    = report["verdict"]
    confidence = report["confidence"]
    ta         = report["token_analysis"]
    pa         = report["permission_analysis"]
    ca         = report["component_analysis"]
    sa         = report["so_analysis"]

    passed     = verdict in ("LIKELY_CLEAN", "SUSPICIOUS")
    suspicious = verdict == "SUSPICIOUS"
    colour     = _YELLOW if suspicious else (_GREEN if passed else _RED)
    label      = "PASSED" if passed else "FAILED"
    bar        = "─" * 50

    print()
    print(f"  {bar}")
    print(f"  {colour}{label}{_RESET}   confidence {confidence:.4f}", end="")
    if suspicious:
        print(f"  {_YELLOW}(suspicious){_RESET}", end="")
    print()
    print(f"  {bar}")

    src      = ta["source_token_count"]
    bin_     = ta["binary_token_count"]
    shared   = ta["intersection_count"]
    bin_only = ta["tokens_only_in_binary"]
    print(f"  Tokens        {src} src · {bin_} bin · {shared} shared · {bin_only} bin-only")

    if pa["dangerous_added"]:
        print(f"  Permissions   {_YELLOW}{len(pa['dangerous_added'])} dangerous added{_RESET}")
    elif pa["added"]:
        print(f"  Permissions   +{len(pa['added'])} added")
    else:
        print("  Permissions   no changes")

    if ca["total_added"]:
        print(f"  Components    +{ca['total_added']} added")
    else:
        print("  Components    no changes")

    if sa["added_libs"]:
        print(f"  Native libs   +{len(sa['added_libs'])} added")
    else:
        print("  Native libs   no changes")

    print(f"  {bar}")
    print()


def main():
    global VERBOSE

    parser = argparse.ArgumentParser(prog="bep")
    parser.add_argument("repo_url", help="GitHub repository URL")
    parser.add_argument("-v", "--verbose", action="store_true", help="show full build output")
    args = parser.parse_args()

    VERBOSE  = args.verbose
    repo_url = args.repo_url

    ensure_aapt2()
    owner, repo = parse_repo_url(repo_url)

    binary_apks = [f for f in os.listdir(BINARY_DIR) if f.endswith(".apk")]
    if not binary_apks:
        die(f"no APK found in {BINARY_DIR}", "NO_BINARY")
    binary_apk = os.path.join(BINARY_DIR, binary_apks[0])
    log(f"binary APK: {binary_apk}")

    version = get_apk_version(binary_apk)
    log(f"binary version: {version or 'unknown'}")

    if VERBOSE:
        ref = find_matching_tag(owner, repo, version) or "main"
        log(f"using ref: {ref}")
    else:
        _spin_start("Fetching release info")
        ref = find_matching_tag(owner, repo, version) or "main"
        _spin_stop("Fetching release info")
        print(f"\n  {owner}/{repo}  ·  {ref}\n")

    log("--- download ---")
    if VERBOSE:
        rc = stream([sys.executable, os.path.join(PIPELINE_DIR, "download.py"), repo_url, ref])
    else:
        _spin_start("Downloading source")
        rc = _run_quiet([sys.executable, os.path.join(PIPELINE_DIR, "download.py"), repo_url, ref])
        _spin_stop("Downloading source", ok=(rc == 0))
    if rc != 0:
        die("download failed", "DOWNLOAD_FAILED")

    log("--- type detection ---")
    result = subprocess.run(
        [sys.executable, os.path.join(PIPELINE_DIR, "type_finder.py"), binary_apk, BUILD_ENV],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        die(f"type_finder failed:\n{result.stdout or result.stderr}", "TYPE_DETECTION_FAILED")
    try:
        detection = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        die(f"type_finder bad output: {result.stdout}", "TYPE_DETECTION_FAILED")

    build_type = detection.get("type", "UNSUPPORTED")
    abi        = detection.get("abi", "arm64-v8a")
    log(f"type={build_type}  abi={abi}")
    if build_type == "UNSUPPORTED":
        die("unsupported project type — cannot build", "UNSUPPORTED_BUILD_TYPE")

    log("--- docker ---")
    if VERBOSE:
        ensure_docker_daemon()
        ensure_docker_image()
    else:
        _spin_start("Preparing build environment")
        _ensure_docker_quiet()
        _spin_stop()

    log("--- docker build + BEP ---")
    cmd = (
        f'docker run --rm'
        f' -v "gradle-cache":/root/.gradle'
        f' -v "android-sdk-cache":/opt/android-sdk'
        f' -v "flutter-pub-cache":/root/.pub-cache'
        f' -v "{to_wsl_path(PIPELINE_DIR)}":/bep/pipeline'
        f' -v "{to_wsl_path(BEP_ENV)}":/bep/BEP_env'
        f' -v "{to_wsl_path(BUILD_ENV)}":/bep/build_env'
        f' {DOCKER_IMAGE}'
        f' python3 /bep/pipeline/runner.py {build_type} {abi}'
    )

    if VERBOSE:
        rc = stream(["wsl", "bash", "-c", cmd])
        if rc != 0:
            die("docker run failed", "BUILD_FAILED")
    else:
        rc, last_verdict = _docker_run_steps(cmd)
        if rc != 0:
            hint = " — run with --verbose for details"
            die(f"{last_verdict or 'BUILD_FAILED'}{hint}", last_verdict or "BUILD_FAILED")

        stem        = os.path.splitext(binary_apks[0])[0]
        report_path = os.path.join(BEP_ENV, stem + "_bep_report.json")
        if not os.path.exists(report_path):
            die("BEP report not found — run with --verbose for details")
        with open(report_path, encoding="utf-8") as f:
            report = json.load(f)
        print_bep_summary(report)


if __name__ == "__main__":
    main()
