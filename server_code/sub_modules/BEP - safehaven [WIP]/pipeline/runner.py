import sys
import os
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BEP_ENV = os.path.join(os.path.dirname(SCRIPT_DIR), "BEP_env")


def log(msg):
    print(f"[runner] {msg}", flush=True)


def die(msg, verdict=None):
    if verdict:
        print(f"\n[verdict] {verdict}", flush=True)
    print(f"[error] {msg}", flush=True)
    sys.exit(1)


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


def main():
    if len(sys.argv) < 3:
        die("usage: python runner.py <build_type> <abi>")

    build_type = sys.argv[1]
    abi = sys.argv[2]

    log(f"type={build_type}  abi={abi}")

    log("--- build ---")
    rc = stream([
        "python3", os.path.join(SCRIPT_DIR, "build_script.py"),
        "--type", build_type,
        "--abi", abi,
    ])
    if rc != 0:
        die("build failed", "BUILD_FAILED")

    log("--- BEP ---")
    rc = stream(["python3", os.path.join(BEP_ENV, "bep_v1.py")], cwd=BEP_ENV)
    if rc != 0:
        die("BEP failed", "BEP_FAILED")


if __name__ == "__main__":
    main()
