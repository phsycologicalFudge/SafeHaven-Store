import urllib.request
import urllib.error
import json
import time
import sys
import math
import os

FDROID_INDEX_URL = "https://f-droid.org/repo/index-v1.json"
WORKER_URL       = "https://api.colourswift.com/admin/store/fdroid-index-chunk"

SECRET           = os.environ.get("WORKER_SECRET", "")

HEADERS = {
    "authorization": SECRET,
    "content-type": "application/json",
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36",
    "accept": "application/json"
}

def send_chunk(data_dict):
    req = urllib.request.Request(
        WORKER_URL,
        data=json.dumps(data_dict).encode('utf-8'),
        method="POST",
        headers=HEADERS
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return res.status, json.loads(res.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

print("Fetching F-Droid index...")
try:
    with urllib.request.urlopen(FDROID_INDEX_URL, timeout=300) as res:
        raw_data = res.read()
    print(f"Downloaded {len(raw_data) / 1024 / 1024:.1f} MB")
except Exception as e:
    print(f"Fetch failed: {e}")
    sys.exit(1)

print("Uploading full index to R2 cache...")
req = urllib.request.Request(
    WORKER_URL.replace("/fdroid-index-chunk", "/fdroid-index"),
    data=raw_data,
    method="PUT",
    headers={
        "authorization": SECRET,
        "content-type": "application/json",
        "user-agent": HEADERS["user-agent"],
    }
)
try:
    with urllib.request.urlopen(req, timeout=120) as res:
        print(f"R2 cache: {res.status}")
except urllib.error.HTTPError as e:
    print(f"R2 cache upload failed: {e.code} - {e.read().decode()}")
    sys.exit(1)

index      = json.loads(raw_data)
apps       = index.get("apps", [])
packages   = index.get("packages", {})
repo_data  = index.get("repo", {})
total_apps = len(apps)

merged_apps = []
for app in apps:
    pkg_name     = app.get("packageName", "")
    pkg_versions = packages.get(pkg_name, [])
    if not pkg_versions:
        continue
    latest = max(pkg_versions, key=lambda x: x.get("versionCode", 0))
    merged_apps.append({**app, **latest})

total_apps   = len(merged_apps)
CHUNK_SIZE   = 100
total_chunks = math.ceil(total_apps / CHUNK_SIZE)

print("Signaling start...")
status, body = send_chunk({
    "type": "repo",
    "data": repo_data,
    "totalApps": total_apps,
    "totalChunks": total_chunks
})
print(f"Start: {status} - {body}")
if status != 200:
    sys.exit("Worker rejected start signal")

print(f"Splitting {total_apps} apps into {total_chunks} chunks of {CHUNK_SIZE}...")

for i in range(0, total_apps, CHUNK_SIZE):
    chunk_index = i // CHUNK_SIZE
    chunk_apps  = merged_apps[i : i + CHUNK_SIZE]

    status, body = send_chunk({
        "type": "apps",
        "chunkIndex": chunk_index,
        "totalChunks": total_chunks,
        "apps": chunk_apps
    })

    if status == 200:
        imported = body.get("imported", 0)
        updated  = body.get("updated", 0)
        print(f"Chunk {chunk_index + 1}/{total_chunks}: OK (Imported: {imported}, Updated: {updated})")
    else:
        print(f"Chunk {chunk_index + 1}/{total_chunks}: FAILED - {body}")

    time.sleep(0.5)

print("Done!")