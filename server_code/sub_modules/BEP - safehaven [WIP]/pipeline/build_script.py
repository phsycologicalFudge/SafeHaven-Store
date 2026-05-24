import sys
import os
import argparse
import shutil
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
BUILD_ENV = os.path.join(ROOT_DIR, "build_env")
BEP_ENV = os.path.join(ROOT_DIR, "BEP_env")
SOURCE_DIR = os.path.join(BEP_ENV, "source")


def log(msg):
    print(f"[build] {msg}", flush=True)


def die(msg):
    print(f"[error] {msg}", flush=True)
    sys.exit(1)


def abi_to_flutter_platform(abi):
    return {
        "arm64-v8a": "arm64",
        "armeabi-v7a": "arm",
        "x86_64": "x64",
        "x86": "x86",
    }.get(abi, "arm64")


def find_sdk_root():
    sdk_root = os.getenv("ANDROID_HOME") or os.getenv("ANDROID_SDK_ROOT") or ""
    if sdk_root and os.path.isdir(sdk_root):
        return sdk_root
    return None


def write_local_properties(project_dir):
    sdk_root = find_sdk_root()
    if not sdk_root:
        log("WARN: could not determine SDK root, skipping local.properties")
        return
    lp = os.path.join(project_dir, "local.properties")
    with open(lp, "w") as f:
        f.write(f"sdk.dir={sdk_root}\n")
    log(f"wrote local.properties: {sdk_root}")


def copy_to_source(apk_path):
    os.makedirs(SOURCE_DIR, exist_ok=True)
    for f in os.listdir(SOURCE_DIR):
        if f.endswith(".apk"):
            os.remove(os.path.join(SOURCE_DIR, f))
    dest = os.path.join(SOURCE_DIR, os.path.basename(apk_path))
    shutil.copy2(apk_path, dest)
    log(f"copied to source: {dest}")


def find_newest_apk(search_root, exclude_unsigned=False):
    candidates = []
    for root, _, files in os.walk(search_root):
        for f in files:
            if not f.endswith(".apk"):
                continue
            if exclude_unsigned and "unsigned" in f.lower():
                continue
            candidates.append(os.path.join(root, f))
    if not candidates and exclude_unsigned:
        return find_newest_apk(search_root, exclude_unsigned=False)
    if not candidates:
        return None
    candidates.sort(key=os.path.getmtime, reverse=True)
    return candidates[0]


def gradlew(project_dir):
    gw = os.path.join(project_dir, "gradlew")
    if os.path.exists(gw):
        os.chmod(gw, 0o755)
        subprocess.run(["sed", "-i", "s/\r//g", gw])
        return gw
    fallback = shutil.which("gradle")
    if fallback:
        return fallback
    die(f"gradlew not found in {project_dir} and gradle not on PATH")


def run(cmd, cwd):
    result = subprocess.run(cmd, cwd=cwd)
    return result.returncode


def build_flutter(abi, fat):
    flutter = shutil.which("flutter")
    if not flutter:
        die("flutter not found on PATH")

    if not os.path.exists(os.path.join(BUILD_ENV, "pubspec.yaml")):
        die("pubspec.yaml not found in build_env")

    log("flutter pub get...")
    rc = run([flutter, "pub", "get"], BUILD_ENV)
    if rc != 0:
        die("flutter pub get failed")

    if fat:
        cmd = [flutter, "build", "apk", "--release"]
    else:
        platform = abi_to_flutter_platform(abi)
        cmd = [flutter, "build", "apk", "--release", "--split-per-abi", f"--target-platform=android-{platform}"]

    log(f"flutter build apk {'(fat)' if fat else f'(split {abi})'}...")
    rc = run(cmd, BUILD_ENV)
    if rc != 0:
        die("flutter build apk failed")

    base = os.path.join(BUILD_ENV, "build", "app", "outputs", "flutter-apk")
    if not os.path.exists(base):
        base = os.path.join(BUILD_ENV, "build", "app", "outputs", "apk", "release")

    if not fat:
        specific = os.path.join(base, f"app-{abi}-release.apk")
        if os.path.exists(specific):
            return specific

    apk = find_newest_apk(os.path.join(BUILD_ENV, "build"))
    if not apk:
        die("flutter built APK not found")
    return apk


def _build_gradle(abi, fat, label, project_dir=None):
    if project_dir is None:
        project_dir = BUILD_ENV
    write_local_properties(project_dir)
    gw = gradlew(project_dir)
    log(f"gradlew assembleRelease ({label})...")
    rc = run(["bash", gw, "assembleRelease"], project_dir)
    if rc != 0:
        die(f"{label} gradlew assembleRelease failed")
    apk = find_newest_apk(project_dir, exclude_unsigned=True)
    if not apk:
        die(f"{label} built APK not found")
    return apk


def build_kotlin(abi, fat):
    write_local_properties(BUILD_ENV)
    gw = gradlew(BUILD_ENV)
    log("gradlew assembleRelease (kotlin)...")
    rc = run(["bash", gw, "assembleRelease"], BUILD_ENV)
    if rc != 0:
        die("kotlin gradlew assembleRelease failed")
    specific = os.path.join(BUILD_ENV, "app", "build", "outputs", "apk", "release")
    apk = find_newest_apk(specific, exclude_unsigned=True) or find_newest_apk(BUILD_ENV, exclude_unsigned=True)
    if not apk:
        die("kotlin built APK not found")
    return apk


def build_native_cpp(abi, fat):
    return _build_gradle(abi, fat, "native_cpp")


def build_react_native(abi, fat):
    android_dir = os.path.join(BUILD_ENV, "android")
    if not os.path.isdir(android_dir):
        die("android/ directory not found in React Native project")

    npm = shutil.which("npm")
    if not npm:
        die("npm not found on PATH")

    log("npm install...")
    rc = run([npm, "install"], BUILD_ENV)
    if rc != 0:
        die("npm install failed")

    return _build_gradle(abi, fat, "react_native", project_dir=android_dir)


BUILDERS = {
    "flutter": build_flutter,
    "kotlin": build_kotlin,
    "react_native": build_react_native,
    "native_cpp": build_native_cpp,
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", required=True, choices=list(BUILDERS.keys()))
    parser.add_argument("--abi", required=True)
    args = parser.parse_args()

    fat = args.abi == "fat"
    abi = args.abi

    log(f"type={args.type}  abi={abi}  fat={fat}")

    apk = BUILDERS[args.type](abi, fat)
    log(f"built APK: {apk}")
    copy_to_source(apk)


if __name__ == "__main__":
    main()
