import sys
import os
import json
import zipfile
from pathlib import Path


def detect_abi(apk_path):
    abis = set()
    try:
        with zipfile.ZipFile(apk_path) as z:
            for name in z.namelist():
                if name.startswith("lib/") and name.count("/") >= 2:
                    abi = name.split("/")[1]
                    if abi:
                        abis.add(abi)
    except Exception:
        pass
    if len(abis) <= 1:
        return next(iter(abis)) if abis else "arm64-v8a"
    return "fat"


def detect_build_type(repo_dir):
    p = Path(repo_dir)

    if (p / "pubspec.yaml").exists():
        return "flutter"

    pkg_json = p / "package.json"
    if pkg_json.exists():
        try:
            data = json.loads(pkg_json.read_text(encoding="utf-8", errors="ignore"))
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
            if "react-native" in deps:
                return "react_native"
        except Exception:
            pass

    gradle_indicators = [
        p / "build.gradle",
        p / "build.gradle.kts",
        p / "app" / "build.gradle",
        p / "app" / "build.gradle.kts",
        p / "settings.gradle",
        p / "settings.gradle.kts",
    ]
    if any(f.exists() for f in gradle_indicators):
        return "kotlin"

    cmake_indicators = list(p.glob("CMakeLists.txt")) + \
                       list(p.glob("app/CMakeLists.txt")) + \
                       list(p.glob("**/Android.mk"))
    if cmake_indicators:
        return "native_cpp"

    return "UNSUPPORTED"


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: type_finder.py <binary_apk> <repo_dir>"}))
        sys.exit(1)

    binary_apk = sys.argv[1]
    repo_dir = sys.argv[2]

    if not os.path.exists(binary_apk):
        print(json.dumps({"error": f"binary APK not found: {binary_apk}"}))
        sys.exit(1)

    if not os.path.isdir(repo_dir):
        print(json.dumps({"error": f"repo dir not found: {repo_dir}"}))
        sys.exit(1)

    abi = detect_abi(binary_apk)
    build_type = detect_build_type(repo_dir)

    print(json.dumps({"type": build_type, "abi": abi}))


if __name__ == "__main__":
    main()
