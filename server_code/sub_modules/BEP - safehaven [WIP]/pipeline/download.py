import sys
import os
import shutil
import stat
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
BUILD_ENV = os.path.join(ROOT_DIR, "build_env")


def log(msg):
    print(f"[download] {msg}", flush=True)


def die(msg):
    print(f"[error] {msg}", flush=True)
    sys.exit(1)


def _force_remove(func, path, exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def main():
    if len(sys.argv) < 3:
        die("usage: python download.py <repo_url> <ref>")

    repo_url = sys.argv[1]
    ref = sys.argv[2]

    if os.path.exists(BUILD_ENV):
        log("removing existing build_env...")
        shutil.rmtree(BUILD_ENV, onerror=_force_remove)

    os.makedirs(BUILD_ENV, exist_ok=True)

    log(f"cloning {repo_url} @ {ref}...")
    result = subprocess.run(
        ["git", "clone", "--depth", "1", "--branch", ref, repo_url, BUILD_ENV],
        capture_output=False,
    )
    if result.returncode != 0:
        shutil.rmtree(BUILD_ENV, ignore_errors=True)
        log(f"branch '{ref}' not found, retrying with default branch...")
        result = subprocess.run(
            ["git", "clone", "--depth", "1", repo_url, BUILD_ENV],
            capture_output=False,
        )
        if result.returncode != 0:
            die("git clone failed")

    log("clone complete")


if __name__ == "__main__":
    main()
