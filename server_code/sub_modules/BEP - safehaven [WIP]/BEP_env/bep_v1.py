from __future__ import annotations

import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

try:
    from androguard.core.bytecodes.axml import AXMLPrinter
except ImportError:
    AXMLPrinter = None


ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

MIN_TOKEN_LEN = 10
MAX_TOKEN_LEN = 96
SCAN_EXTS = (".dex", ".so")
SCAN_EXACT = {"androidmanifest.xml"}

ASCII_RUN_RE = re.compile(rb"[ -~]{10,96}")
TOKEN_RE = re.compile(rb"[A-Za-z0-9_./:$@%#?=&,+\-]{10,96}")

FRAMEWORK_NOISE_RE = re.compile(
    r"^(?:"
    r"androidx/|android/support/|android/|"
    r"Landroidx/|Landroid/support/|Landroid/|"
    r"Ljava/|"
    r"Lkotlin/|kotlin/|Lkotlinx/|kotlinx/|"
    r"Lorg/jetbrains/|org/jetbrains/|"
    r"Ldalvik/|dalvik/|"
    r"Lorg/apache/|org/apache/|Lorg/json/|org/json/|"
    r"Lcom/google/|com/google/|Lcom/android/|com/android/|"
    r"Lokhttp3/|okhttp3/|Lokio/|okio/|Lretrofit2/|retrofit2/|"
    r"Lcom/squareup/|com/squareup/|"
    r"Lcom/google/gson/|com/google/gson/|"
    r"Lcom/google/protobuf/|com/google/protobuf/|"
    r"Ldagger/|dagger/|"
    r"Lio/reactivex/|io/reactivex/|"
    r"Lcom/bumptech/glide/|com/bumptech/glide/|"
    r"Lcoil/|coil/|Lcoil3/|coil3/|"
    r"Lcom/airbnb/lottie/|com/airbnb/lottie/|"
    r"Lcom/facebook/react/|com/facebook/react/|"
    r"Lcom/facebook/soloader/|com/facebook/soloader/|"
    r"Lio/flutter/|io/flutter/|"
    r"Lorg/chromium/|org/chromium/|"
    r"Lcom/unity3d/|com/unity3d/|"
    r"R\$|BuildConfig|Manifest\$|"
    r"Hilt_|Dagger[A-Z]|"
    r".*\$ExternalSyntheticLambda\d*|.*\$\$ExternalSynthetic.*|"
    r".*\$\$Lambda\$.*|.*\$Lambda\$.*"
    r")",
    re.IGNORECASE,
)

SDK_INTERNAL_RE = re.compile(
    r"(?:"
    r"\$Creator|\$Serializer|\$Builder|\$Factory|\$Adapter|\$Stub|\$Proxy|"
    r"TypeAdapter|JsonAdapter|GsonBuilder|ObjectMapper|"
    r"SafeParcelReader|SafeParcelWriter|AbstractSafeParcelable|"
    r"Coroutine|CoroutineContext|CoroutineDispatcher|Dispatchers|Continuation|"
    r"DefaultConstructorMarker|Intrinsics|NoWhenBranchMatchedException|"
    r"CollectionsKt|StringsKt|MapsKt|ArraysKt|"
    r"DataBinderMapperImpl|ViewDataBinding|DataBindingUtil|"
    r"GeneratedMessageLite|ProtoAdapter|KSerializer|"
    r"MembersInjector|DoubleCheck"
    r")",
    re.IGNORECASE,
)

JUNK_SHAPE_RE = re.compile(
    r"(?:^[^A-Za-z0-9]{6,}$|[ZxK<>\-=]{10,}|(?:[_\-+=/\\|]){8,}|(?:[A-F0-9]{2}){12,})"
)

HIGH_ENTROPY_ALPHANUM_RE = re.compile(r"^[A-Za-z0-9+/]{32,}={0,2}$")
REPEATING_PATTERN_RE = re.compile(r"(.{2,6})\1{3,}")
DEMANGLED_SYMBOL_RE = re.compile(r"^_Z[A-Za-z0-9_]+$")
PRIVATE_IP_RE = re.compile(
    r"\b(?:localhost|127(?:\.\d{1,3}){3}|10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|10\.0\.2\.2)\b",
    re.IGNORECASE,
)

RESOURCE_PATH_RE = re.compile(
    r"^res/(drawable|layout|mipmap|anim|color|font|menu|raw|xml|values|navigation)(-[a-z0-9_]+)*/",
    re.IGNORECASE,
)
STATIC_EXT_RE = re.compile(
    r"\.(png|jpe?g|webp|gif|svg|ico|bmp|mp3|wav|ogg|mp4|webm|ttf|otf|woff2?)$",
    re.IGNORECASE,
)

KNOWN_DANGEROUS_PERMISSIONS = {
    "android.permission.SEND_SMS",
    "android.permission.READ_SMS",
    "android.permission.RECEIVE_SMS",
    "android.permission.RECEIVE_MMS",
    "android.permission.RECEIVE_WAP_PUSH",
    "android.permission.READ_CONTACTS",
    "android.permission.WRITE_CONTACTS",
    "android.permission.READ_CALL_LOG",
    "android.permission.WRITE_CALL_LOG",
    "android.permission.PROCESS_OUTGOING_CALLS",
    "android.permission.READ_PHONE_STATE",
    "android.permission.CALL_PHONE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.RECORD_AUDIO",
    "android.permission.CAMERA",
    "android.permission.BIND_ACCESSIBILITY_SERVICE",
    "android.permission.BIND_DEVICE_ADMIN",
    "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE",
    "android.permission.REQUEST_INSTALL_PACKAGES",
    "android.permission.SYSTEM_ALERT_WINDOW",
    "android.permission.WRITE_SETTINGS",
    "android.permission.CHANGE_NETWORK_STATE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    "android.permission.GET_ACCOUNTS",
    "android.permission.USE_CREDENTIALS",
    "android.permission.BIND_VPN_SERVICE",
}

ELF_MAGIC = b"\x7fELF"


def _alpha_ratio(s: str) -> float:
    if not s:
        return 0.0
    return sum(1 for c in s if c.isalpha()) / len(s)


def _unique_char_ratio(s: str) -> float:
    if not s:
        return 0.0
    return len(set(s)) / len(s)


def is_noise_token(s: str) -> bool:
    if not s or len(s) < MIN_TOKEN_LEN:
        return True
    if FRAMEWORK_NOISE_RE.match(s):
        return True
    if SDK_INTERNAL_RE.search(s):
        return True
    if JUNK_SHAPE_RE.search(s):
        return True
    if HIGH_ENTROPY_ALPHANUM_RE.match(s):
        return True
    if REPEATING_PATTERN_RE.search(s):
        return True
    if DEMANGLED_SYMBOL_RE.match(s):
        return True
    if PRIVATE_IP_RE.match(s):
        return True
    if RESOURCE_PATH_RE.match(s):
        return True
    if STATIC_EXT_RE.search(s):
        return True
    if _alpha_ratio(s) < 0.30:
        return True
    if _unique_char_ratio(s) < 0.18:
        return True
    return False


def extract_tokens_from_buffer(buf: bytes) -> Set[str]:
    found: Set[str] = set()
    for pattern in (ASCII_RUN_RE, TOKEN_RE):
        for m in pattern.finditer(buf):
            raw = m.group(0)
            if b"\x00" in raw:
                continue
            try:
                s = raw.decode("utf-8", errors="strict").strip()
            except UnicodeDecodeError:
                continue
            if len(s) < MIN_TOKEN_LEN or len(s) > MAX_TOKEN_LEN:
                continue
            if "\n" in s or "\r" in s or "\t" in s:
                continue
            if not is_noise_token(s):
                found.add(s)
    return found


def should_scan_entry(name: str) -> bool:
    nl = name.lower()
    if nl.startswith("meta-inf/"):
        return False
    if nl in SCAN_EXACT:
        return True
    return nl.endswith(SCAN_EXTS)


def extract_tokens_from_apk(apk_path: Path) -> Set[str]:
    tokens: Set[str] = set()
    try:
        with zipfile.ZipFile(apk_path) as zf:
            for info in zf.infolist():
                if not should_scan_entry(info.filename):
                    continue
                if info.file_size <= 0 or info.file_size > 32 * 1024 * 1024:
                    continue
                try:
                    buf = zf.read(info.filename)
                except Exception:
                    continue
                tokens |= extract_tokens_from_buffer(buf)
    except Exception as e:
        print(f"  [WARN] token extraction failed for {apk_path.name}: {e}")
    return tokens


def read_manifest_bytes(apk_path: Path) -> Optional[bytes]:
    try:
        with zipfile.ZipFile(apk_path) as zf:
            for info in zf.infolist():
                if info.filename.lower() == "androidmanifest.xml":
                    return zf.read(info.filename)
    except Exception:
        pass
    return None


def decode_manifest(raw: bytes) -> Optional[str]:
    if not raw:
        return None
    if AXMLPrinter is not None:
        try:
            ax = AXMLPrinter(raw)
            xm = ax.get_xml()
            if isinstance(xm, bytes):
                return xm.decode("utf-8", errors="ignore")
            return str(xm)
        except Exception:
            pass
    try:
        return raw.decode("utf-8", errors="ignore")
    except Exception:
        return None


def attr(elem, name: str) -> Optional[str]:
    return (
        elem.attrib.get(ANDROID_NS + name)
        or elem.attrib.get("android:" + name)
        or elem.attrib.get(name)
    )


def parse_manifest(xml_text: str) -> Optional[ET.Element]:
    if not xml_text:
        return None
    try:
        return ET.fromstring(xml_text)
    except Exception:
        try:
            cleaned = re.sub(r"^\s*<\?xml[^>]*\?>", "", xml_text, flags=re.IGNORECASE).strip()
            return ET.fromstring(cleaned)
        except Exception:
            return None


def extract_manifest_data(apk_path: Path) -> Dict:
    raw = read_manifest_bytes(apk_path)
    if raw is None:
        return {"permissions": set(), "components": {}, "package": None, "version_code": None}

    xml_text = decode_manifest(raw)
    root = parse_manifest(xml_text) if xml_text else None

    permissions: Set[str] = set()
    components: Dict[str, List[str]] = {"activity": [], "service": [], "receiver": [], "provider": []}
    package = None
    version_code = None

    if root is None:
        return {"permissions": permissions, "components": components, "package": package, "version_code": version_code}

    package = root.attrib.get("package")
    version_code = root.attrib.get(ANDROID_NS + "versionCode") or root.attrib.get("android:versionCode")

    for child in root:
        tag = child.tag.split("}", 1)[-1] if isinstance(child.tag, str) else child.tag
        if tag in ("uses-permission", "uses-permission-sdk-23"):
            name = attr(child, "name")
            if name:
                permissions.add(name.strip())
        elif tag == "application":
            for subchild in child:
                subtag = subchild.tag.split("}", 1)[-1] if isinstance(subchild.tag, str) else subchild.tag
                if subtag in components:
                    name = attr(subchild, "name")
                    if name:
                        components[subtag].append(name.strip())

    return {
        "permissions": permissions,
        "components": components,
        "package": package,
        "version_code": version_code,
    }


def extract_so_info(apk_path: Path) -> Tuple[Set[str], int]:
    names: Set[str] = set()
    count = 0
    try:
        with zipfile.ZipFile(apk_path) as zf:
            for info in zf.infolist():
                if info.filename.lower().endswith(".so"):
                    count += 1
                    parts = info.filename.replace("\\", "/").split("/")
                    names.add(parts[-1])
    except Exception:
        pass
    return names, count


def safe_div(a: float, b: float) -> float:
    return a / b if b > 0 else 0.0


def find_apk(folder: Path) -> Optional[Path]:
    return next((p for p in folder.iterdir() if p.suffix.lower() == ".apk"), None)


def score_bep(source_apk: Path, binary_apk: Path) -> Dict:
    print(f"[BEP] Source: {source_apk.name}")
    print(f"[BEP] Binary: {binary_apk.name}")

    print("[1/4] Extracting tokens...")
    src_tokens = extract_tokens_from_apk(source_apk)
    bin_tokens = extract_tokens_from_apk(binary_apk)
    print(f"      source={len(src_tokens)} binary={len(bin_tokens)}")

    print("[2/4] Parsing manifests...")
    src_manifest = extract_manifest_data(source_apk)
    bin_manifest = extract_manifest_data(binary_apk)

    print("[3/4] Extracting .so info...")
    src_so, src_so_count = extract_so_info(source_apk)
    bin_so, bin_so_count = extract_so_info(binary_apk)

    print("[4/4] Computing scores...")

    intersection = src_tokens & bin_tokens
    forward_coverage = safe_div(len(intersection), len(src_tokens))
    reverse_coverage = safe_div(len(intersection), len(bin_tokens))

    src_perms = src_manifest["permissions"]
    bin_perms = bin_manifest["permissions"]
    added_perms = bin_perms - src_perms
    removed_perms = src_perms - bin_perms

    dangerous_added = added_perms & KNOWN_DANGEROUS_PERMISSIONS
    perm_delta = len(added_perms)
    dangerous_perm_delta = len(dangerous_added)

    src_components = src_manifest["components"]
    bin_components = bin_manifest["components"]
    added_components: Dict[str, List[str]] = {}
    removed_components: Dict[str, List[str]] = {}
    for kind in ("activity", "service", "receiver", "provider"):
        src_set = set(src_components.get(kind, []))
        bin_set = set(bin_components.get(kind, []))
        added = bin_set - src_set
        removed = src_set - bin_set
        if added:
            added_components[kind] = sorted(added)
        if removed:
            removed_components[kind] = sorted(removed)

    added_so = bin_so - src_so
    removed_so = src_so - bin_so
    so_count_delta = bin_so_count - src_so_count

    confidence = 1.0

    if forward_coverage < 0.30:
        confidence *= 0.40
    elif forward_coverage < 0.50:
        confidence *= 0.65
    elif forward_coverage < 0.70:
        confidence *= 0.85

    if reverse_coverage < 0.30:
        confidence *= 0.25
    elif reverse_coverage < 0.50:
        confidence *= 0.50
    elif reverse_coverage < 0.70:
        confidence *= 0.75
    elif reverse_coverage < 0.85:
        confidence *= 0.90

    if dangerous_perm_delta >= 2:
        confidence *= 0.10
    elif dangerous_perm_delta == 1:
        confidence *= 0.35
    elif perm_delta >= 3:
        confidence *= 0.70
    elif perm_delta >= 1:
        confidence *= 0.88

    total_added_components = sum(len(v) for v in added_components.values())
    if total_added_components >= 3:
        confidence *= 0.60
    elif total_added_components >= 1:
        confidence *= 0.82

    if len(added_so) >= 2:
        confidence *= 0.65
    elif len(added_so) == 1:
        confidence *= 0.82

    confidence = round(max(0.0, min(1.0, confidence)), 4)

    if confidence >= 0.85:
        verdict = "LIKELY_CLEAN"
    elif confidence >= 0.65:
        verdict = "SUSPICIOUS"
    elif confidence >= 0.40:
        verdict = "LIKELY_TAMPERED"
    else:
        verdict = "TAMPERED"

    return {
        "verdict": verdict,
        "confidence": confidence,
        "source_apk": str(source_apk),
        "binary_apk": str(binary_apk),
        "token_analysis": {
            "source_token_count": len(src_tokens),
            "binary_token_count": len(bin_tokens),
            "intersection_count": len(intersection),
            "forward_coverage": round(forward_coverage, 4),
            "reverse_coverage": round(reverse_coverage, 4),
            "tokens_only_in_binary": len(bin_tokens - src_tokens),
            "tokens_only_in_source": len(src_tokens - bin_tokens),
        },
        "permission_analysis": {
            "source_count": len(src_perms),
            "binary_count": len(bin_perms),
            "added": sorted(added_perms),
            "removed": sorted(removed_perms),
            "dangerous_added": sorted(dangerous_added),
            "delta": perm_delta,
            "dangerous_delta": dangerous_perm_delta,
        },
        "component_analysis": {
            "added": added_components,
            "removed": removed_components,
            "total_added": total_added_components,
        },
        "so_analysis": {
            "source_count": src_so_count,
            "binary_count": bin_so_count,
            "count_delta": so_count_delta,
            "added_libs": sorted(added_so),
            "removed_libs": sorted(removed_so),
        },
        "manifest_meta": {
            "source_package": src_manifest["package"],
            "binary_package": bin_manifest["package"],
            "source_version_code": src_manifest["version_code"],
            "binary_version_code": bin_manifest["version_code"],
        },
    }


def print_report(report: Dict) -> None:
    v = report["verdict"]
    c = report["confidence"]
    ta = report["token_analysis"]
    pa = report["permission_analysis"]
    ca = report["component_analysis"]
    sa = report["so_analysis"]
    mm = report["manifest_meta"]

    verdict_colours = {
        "LIKELY_CLEAN": "\033[92m",
        "SUSPICIOUS": "\033[93m",
        "LIKELY_TAMPERED": "\033[91m",
        "TAMPERED": "\033[91m",
    }
    reset = "\033[0m"
    colour = verdict_colours.get(v, "")

    print()
    print("=" * 60)
    print(f"  BEP RESULT: {colour}{v}{reset}  (confidence {c:.4f})")
    print("=" * 60)

    print()
    print(f"  Packages : {mm['source_package']} / {mm['binary_package']}")
    print(f"  Versions : {mm['source_version_code']} / {mm['binary_version_code']}")

    print()
    print("  TOKEN COVERAGE")
    print(f"    Source tokens       : {ta['source_token_count']}")
    print(f"    Binary tokens       : {ta['binary_token_count']}")
    print(f"    Intersection        : {ta['intersection_count']}")
    print(f"    Forward coverage    : {ta['forward_coverage']:.4f}  (source -> binary)")
    print(f"    Reverse coverage    : {ta['reverse_coverage']:.4f}  (binary <- source)")
    print(f"    Only in binary      : {ta['tokens_only_in_binary']}  <-- injection signal")
    print(f"    Only in source      : {ta['tokens_only_in_source']}  <-- stripping/R8")

    print()
    print("  PERMISSIONS")
    print(f"    Source / Binary     : {pa['source_count']} / {pa['binary_count']}")
    if pa["dangerous_added"]:
        print(f"    Dangerous added     : {pa['dangerous_added']}")
    if pa["added"]:
        print(f"    Added               : {pa['added']}")
    if pa["removed"]:
        print(f"    Removed             : {pa['removed']}")
    if not pa["added"] and not pa["removed"]:
        print("    No permission delta.")

    print()
    print("  COMPONENTS")
    if ca["total_added"] == 0 and not ca["removed"]:
        print("    No component delta.")
    else:
        for kind, names in ca["added"].items():
            print(f"    Added {kind}s   : {names}")
        for kind, names in ca["removed"].items():
            print(f"    Removed {kind}s : {names}")

    print()
    print("  NATIVE LIBS (.so)")
    print(f"    Source / Binary     : {sa['source_count']} / {sa['binary_count']}  (delta {sa['count_delta']:+d})")
    if sa["added_libs"]:
        print(f"    Added libs          : {sa['added_libs']}")
    if sa["removed_libs"]:
        print(f"    Removed libs        : {sa['removed_libs']}")
    if not sa["added_libs"] and not sa["removed_libs"]:
        print("    No .so delta.")

    print()
    print("=" * 60)


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=None)
    parser.add_argument("--binary", type=Path, default=None)
    parser.add_argument("--source-dir", type=Path, default=None)
    parser.add_argument("--binary-dir", type=Path, default=None)
    args = parser.parse_args()

    base = Path(__file__).parent

    if args.source and args.binary:
        source_apk = args.source
        binary_apk = args.binary
    else:
        source_dir = args.source_dir or base / "source"
        binary_dir = args.binary_dir or base / "binary"

        if not source_dir.is_dir():
            print(f"Missing source folder: {source_dir}")
            sys.exit(1)
        if not binary_dir.is_dir():
            print(f"Missing binary folder: {binary_dir}")
            sys.exit(1)

        source_apk = find_apk(source_dir)
        if source_apk is None:
            print(f"No APK found in source/: {source_dir}")
            sys.exit(1)

        binary_apk = find_apk(binary_dir)
        if binary_apk is None:
            print(f"No APK found in binary/: {binary_dir}")
            sys.exit(1)

    if AXMLPrinter is None:
        print("[WARN] androguard not installed — manifest parsing disabled, token analysis only")
        print("       pip install androguard==3.3.5")

    report = score_bep(source_apk, binary_apk)
    print_report(report)

    out_path = base / (binary_apk.stem + "_bep_report.json")
    out_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False, default=list), encoding="utf-8"
    )
    print(f"\n  JSON report: {out_path}\n")


if __name__ == "__main__":
    main()
