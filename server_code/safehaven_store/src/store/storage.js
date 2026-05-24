const nowUnix = () => Math.floor(Date.now() / 1000);

const INDEX_KEY = "index.json";
const SEVEN_DAYS_SEC = 7 * 24 * 60 * 60;
const CHANGELOG_KEY = "index_changelog.json";

const hmacSha256 = async (key, message) => {
  const k = typeof key === "string" ? new TextEncoder().encode(key) : key;
  const cryptoKey = await crypto.subtle.importKey(
    "raw", k, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  return new Uint8Array(
    await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message))
  );
};

export const sha256Hex = async (data) => {
  const buf = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash), (b) => b.toString(16).padStart(2, "0")).join("");
};

const toHex = (bytes) =>
  Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

const getSigningKey = async (secretKey, dateStamp, region, service) => {
  const kDate    = await hmacSha256("AWS4" + secretKey, dateStamp);
  const kRegion  = await hmacSha256(kDate, region);
  const kService = await hmacSha256(kRegion, service);
  return hmacSha256(kService, "aws4_request");
};

const amzDateOf   = (d) => d.toISOString().replace(/[:\-]|\.\d{3}/g, "").slice(0, 15) + "Z";
const dateStampOf = (d) => d.toISOString().slice(0, 10).replace(/-/g, "");

const cfg = (env) => ({
  endpoint:  (env.SH_S3_ENDPOINT  || "").replace(/\/$/, ""),
  bucket:    env.SH_S3_BUCKET    || "",
  region:    env.SH_S3_REGION    || "nbg1",
  accessKey: env.SH_S3_ACCESS_KEY || "",
  secretKey: env.SH_S3_SECRET_KEY || "",
});

const EMPTY_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

const s3Fetch = async (env, method, key, body = null, extraHeaders = {}) => {
  const c         = cfg(env);
  const now       = new Date();
  const amzDate   = amzDateOf(now);
  const datestamp = dateStampOf(now);

  const url  = `${c.endpoint}/${c.bucket}/${key}`;
  const host = new URL(url).host;

  const payloadHash = body !== null ? await sha256Hex(body) : EMPTY_HASH;

  const rawHeaders = {
    host,
    "x-amz-date":           amzDate,
    "x-amz-content-sha256": payloadHash,
    ...Object.fromEntries(
      Object.entries(extraHeaders).map(([k, v]) => [k.toLowerCase(), String(v)])
    ),
  };

  const sortedKeys       = Object.keys(rawHeaders).sort();
  const signedHeaders    = sortedKeys.join(";");
  const canonicalHeaders = sortedKeys.map((k) => `${k}:${rawHeaders[k]}`).join("\n") + "\n";

  const canonicalRequest = [
    method,
    `/${c.bucket}/${key}`,
    "",
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join("\n");

  const credentialScope = `${datestamp}/${c.region}/s3/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const signingKey    = await getSigningKey(c.secretKey, datestamp, c.region, "s3");
  const signature     = toHex(await hmacSha256(signingKey, stringToSign));
  const authorization = `AWS4-HMAC-SHA256 Credential=${c.accessKey}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const fetchHeaders = {
    ...Object.fromEntries(sortedKeys.filter((k) => k !== "host").map((k) => [k, rawHeaders[k]])),
    Authorization: authorization,
  };

  if (body !== null) {
    fetchHeaders["content-length"] = String(
      typeof body === "string"
        ? new TextEncoder().encode(body).byteLength
        : (body.byteLength ?? body.length)
    );
  }

  return fetch(url, { method, headers: fetchHeaders, body: body ?? undefined });
};

const presignedPutUrl = async (env, key, expiresIn) => {
  const c         = cfg(env);
  const now       = new Date();
  const amzDate   = amzDateOf(now);
  const datestamp = dateStampOf(now);
  const host      = new URL(c.endpoint).host;

  const credentialScope = `${datestamp}/${c.region}/s3/aws4_request`;

  const params = new URLSearchParams({
    "X-Amz-Algorithm":     "AWS4-HMAC-SHA256",
    "X-Amz-Credential":    `${c.accessKey}/${credentialScope}`,
    "X-Amz-Date":          amzDate,
    "X-Amz-Expires":       String(expiresIn),
    "X-Amz-SignedHeaders": "host",
  });

  const canonicalQueryString = params.toString();

  const canonicalRequest = [
    "PUT",
    `/${c.bucket}/${key}`,
    canonicalQueryString,
    `host:${host}\n`,
    "host",
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const signingKey = await getSigningKey(c.secretKey, datestamp, c.region, "s3");
  const signature  = toHex(await hmacSha256(signingKey, stringToSign));

  return `${c.endpoint}/${c.bucket}/${key}?${canonicalQueryString}&X-Amz-Signature=${signature}`;
};

const presignedGetUrl = async (env, key, expiresIn) => {
  const c = cfg(env);
  const now = new Date();
  const amzDate = amzDateOf(now);
  const datestamp = dateStampOf(now);
  const host = new URL(c.endpoint).host;
  const credentialScope = `${datestamp}/${c.region}/s3/aws4_request`;
  const params = new URLSearchParams({
    "X-Amz-Algorithm":     "AWS4-HMAC-SHA256",
    "X-Amz-Credential":    `${c.accessKey}/${credentialScope}`,
    "X-Amz-Date":          amzDate,
    "X-Amz-Expires":       String(expiresIn),
    "X-Amz-SignedHeaders": "host",
  });
  const canonicalQueryString = params.toString();
  const canonicalRequest = ["GET", `/${c.bucket}/${key}`, canonicalQueryString, `host:${host}\n`, "host", "UNSIGNED-PAYLOAD"].join("\n");
  const stringToSign = ["AWS4-HMAC-SHA256", amzDate, credentialScope, await sha256Hex(canonicalRequest)].join("\n");
  const signingKey = await getSigningKey(c.secretKey, datestamp, c.region, "s3");
  const signature = toHex(await hmacSha256(signingKey, stringToSign));
  return `${c.endpoint}/${c.bucket}/${key}?${canonicalQueryString}&X-Amz-Signature=${signature}`;
};

export const CATEGORIES = {
  security:      "Security",
  productivity:  "Productivity",
  utilities:     "Utilities",
  communication: "Communication",
  entertainment: "Entertainment",
  finance:       "Finance",
  health:        "Health & Fitness",
  education:     "Education",
  tools:         "Tools",
  other:         "Other",
};

const emptyIndex = () => ({ version: 1, timestamp: nowUnix(), categories: CATEGORIES, apps: [] });

export const IMAGE_SLOTS = [
  "icon",
  "screenshot_1",
  "screenshot_2",
  "screenshot_3",
  "screenshot_4",
  "screenshot_5",
  "screenshot_6",
];

export const ALLOWED_IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp"];
export const MAX_IMAGE_BYTES     = 2 * 1024 * 1024;

export const apkKey     = (packageName, versionCode) => `apps/${packageName}/${versionCode}/app.apk`;
export const stagingKey = (packageName, versionCode) => `staging/${packageName}/${versionCode}/app.apk`;
export const imageKey   = (packageName, slot)        => `images/${packageName}/${slot}`;

export const getIndex = async (env) => {
  const res = await s3Fetch(env, "GET", INDEX_KEY);
  if (res.status === 404) return emptyIndex();
  if (!res.ok) throw new Error(`index_fetch_failed:${res.status}`);
  return res.json();
};

export const putIndex = async (env, index) => {
  index.timestamp = nowUnix();
  const body = JSON.stringify(index);
  const res  = await s3Fetch(env, "PUT", INDEX_KEY, body, { "content-type": "application/json" });
  if (!res.ok) throw new Error(`index_put_failed:${res.status}`);
};

export const getChangelog = async (env) => {
  const res = await s3Fetch(env, "GET", CHANGELOG_KEY);
  if (res.status === 404) return { events: [] };
  if (!res.ok) throw new Error(`changelog_fetch_failed:${res.status}`);
  return res.json();
};

export const putIndexWithChangelog = async (env, newIndex) => {
  const now = nowUnix();
  newIndex.timestamp = now;

  let oldIndex;
  try {
    oldIndex = await getIndex(env);
  } catch {
    oldIndex = emptyIndex();
  }

  const updates = [];
  for (const newApp of newIndex.apps) {
    const oldApp = oldIndex.apps.find((a) => a.packageName === newApp.packageName);
    if (!oldApp || JSON.stringify(oldApp) !== JSON.stringify(newApp)) {
      updates.push(newApp);
    }
  }

  const removes = oldIndex.apps
    .filter((oa) => !newIndex.apps.find((na) => na.packageName === oa.packageName))
    .map((oa) => oa.packageName);

  if (updates.length > 0 || removes.length > 0) {
    const changelog = await getChangelog(env);
    
    changelog.events.push({
      timestamp: now,
      updates,
      removes,
    });

    const cutoff = now - SEVEN_DAYS_SEC;
    changelog.events = changelog.events.filter((e) => e.timestamp >= cutoff);

    await s3Fetch(env, "PUT", CHANGELOG_KEY, JSON.stringify(changelog), {
      "content-type": "application/json",
    });
  }

  await putIndex(env, newIndex);
};

export const addOrUpdateApp = async (env, appEntry) => {
  const index = await getIndex(env);
  index.categories = CATEGORIES;
  const i = index.apps.findIndex((a) => a.packageName === appEntry.packageName);
  if (i === -1) {
    index.apps.push({ ...appEntry, added: nowUnix(), versions: appEntry.versions ?? [], ratingAvg: null, ratingCount: 0 });
  } else {
    index.apps[i] = {
      ...index.apps[i],
      ...appEntry,
      added:       index.apps[i].added,
      versions:    index.apps[i].versions,
      ratingAvg:   index.apps[i].ratingAvg   ?? null,
      ratingCount: index.apps[i].ratingCount ?? 0,
    };
  }
  index.apps.sort((a, b) => a.packageName.localeCompare(b.packageName));
  await putIndexWithChangelog(env, index);
};

export const addVersionToApp = async (env, packageName, versionEntry) => {
  const index = await getIndex(env);
  const app   = index.apps.find((a) => a.packageName === packageName);
  if (!app) throw new Error("app_not_found");

  app.versions = app.versions ?? [];
  const vi = app.versions.findIndex((v) => v.versionCode === versionEntry.versionCode);
  if (vi === -1) {
    app.versions.push(versionEntry);
  } else {
    app.versions[vi] = versionEntry;
  }
  app.versions.sort((a, b) => b.versionCode - a.versionCode);
  app.lastUpdated = nowUnix();

  await putIndexWithChangelog(env, index);
};

export const removeVersionFromApp = async (env, packageName, versionCode) => {
  const index = await getIndex(env);
  const app   = index.apps.find((a) => a.packageName === packageName);
  if (!app) return;
  app.versions    = (app.versions ?? []).filter((v) => v.versionCode !== versionCode);
  app.lastUpdated = nowUnix();
  await putIndex(env, index);
};

export const removeApp = async (env, packageName) => {
  const index = await getIndex(env);
  index.apps  = index.apps.filter((a) => a.packageName !== packageName);
  await putIndex(env, index);
};

export const updateAppRating = async (env, packageName, ratingSum, ratingCount) => {
  const index = await getIndex(env);
  const app   = index.apps.find((a) => a.packageName === packageName);
  if (!app) return;
  app.ratingAvg   = ratingCount > 0 ? Math.round((ratingSum / ratingCount) * 10) / 10 : null;
  app.ratingCount = ratingCount;
  await putIndex(env, index);
};

export const getPresignedUploadUrl = (env, packageName, versionCode, expiresIn = 900) =>
  presignedPutUrl(env, apkKey(packageName, versionCode), expiresIn);

export const getPresignedStagingUploadUrl = (env, packageName, versionCode, expiresIn = 900) =>
  presignedPutUrl(env, stagingKey(packageName, versionCode), expiresIn);

export const getPresignedDownloadUrl = (env, key, expiresIn = 900) =>
  presignedGetUrl(env, key, expiresIn);

export const getPresignedImageUploadUrl = (env, packageName, slot, expiresIn = 900) =>
  presignedPutUrl(env, imageKey(packageName, slot), expiresIn);

export const getPresignedImageReadUrl = (env, key, expiresIn = 604800) =>
  presignedGetUrl(env, key, expiresIn);

export const putImageObject = async (env, packageName, slot, body, contentType) => {
  const cleanContentType = (contentType || "").toString().split(";")[0].trim().toLowerCase();

  if (!IMAGE_SLOTS.includes(slot)) throw new Error("invalid_image_slot");
  if (!ALLOWED_IMAGE_TYPES.includes(cleanContentType)) throw new Error("invalid_image_type");

  const size = body?.byteLength ?? body?.length ?? 0;
  if (!size) throw new Error("empty_image");
  if (size > MAX_IMAGE_BYTES) throw new Error("image_too_large");

  const key = imageKey(packageName, slot);
  const res = await s3Fetch(env, "PUT", key, body, { "content-type": cleanContentType });
  if (!res.ok) throw new Error(`image_put_failed:${res.status}`);
  return key;
};

export const publicImageUrl = (env, key) => {
  const c = cfg(env);
  return `${c.endpoint}/${c.bucket}/${key}`;
};

export const copyToProduction = async (env, packageName, versionCode) => {
  const c      = cfg(env);
  const source = `/${c.bucket}/${stagingKey(packageName, versionCode)}`;
  const dest   = apkKey(packageName, versionCode);
  const res    = await s3Fetch(env, "PUT", dest, null, { "x-amz-copy-source": source });
  if (!res.ok) throw new Error(`copy_failed:${res.status}`);
};

export const copyStagingToProduction = async (env, sourcePackageName, destPackageName, versionCode) => {
  const c      = cfg(env);
  const source = `/${c.bucket}/${stagingKey(sourcePackageName, versionCode)}`;
  const dest   = apkKey(destPackageName, versionCode);

  const res = await s3Fetch(env, "PUT", dest, null, { "x-amz-copy-source": source });
  if (!res.ok) throw new Error(`copy_failed:${res.status}`);
};

export const promoteStagingToProduction = async (env, stagingKeyStr, prodKeyStr) => {
  const c = cfg(env);
  const res = await s3Fetch(env, "PUT", prodKeyStr, null, { "x-amz-copy-source": `/${c.bucket}/${stagingKeyStr}` });
  if (!res.ok) throw new Error(`promote_failed:${res.status}`);
  await s3Fetch(env, "DELETE", stagingKeyStr);
};

export const deleteStagingApk = async (env, packageName, versionCode) => {
  const res = await s3Fetch(env, "DELETE", stagingKey(packageName, versionCode));
  if (!res.ok && res.status !== 404) throw new Error(`staging_delete_failed:${res.status}`);
};

export const deleteApk = async (env, packageName, versionCode) => {
  const res = await s3Fetch(env, "DELETE", apkKey(packageName, versionCode));
  if (!res.ok && res.status !== 404) throw new Error(`apk_delete_failed:${res.status}`);
};

export const headStagingObject = async (env, packageName, versionCode) => {
  const key = stagingKey(packageName, versionCode);
  const res = await s3Fetch(env, "HEAD", key);
  const contentLengthHeader = res.headers.get("content-length");
  const etag = res.headers.get("etag");
  const contentLength = contentLengthHeader !== null ? Number(contentLengthHeader) : null;
  return {
    ok: res.ok,
    status: res.status,
    key,
    contentLength: Number.isFinite(contentLength) ? contentLength : null,
    etag,
    contentRange: "",
  };
};