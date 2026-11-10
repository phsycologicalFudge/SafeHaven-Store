// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { apkKey, stagingKey, imageKey } from "./constants.js";

export const hmacSha256 = async (key, message) => {
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

export const toHex = (bytes) =>
  Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

export const getSigningKey = async (secretKey, dateStamp, region, service) => {
  const kDate    = await hmacSha256("AWS4" + secretKey, dateStamp);
  const kRegion  = await hmacSha256(kDate, region);
  const kService = await hmacSha256(kRegion, service);
  return hmacSha256(kService, "aws4_request");
};

export const amzDateOf   = (d) => d.toISOString().replace(/[:\-]|\.\d{3}/g, "").slice(0, 15) + "Z";

export const dateStampOf = (d) => d.toISOString().slice(0, 10).replace(/-/g, "");

export const cfg = (env) => ({
  endpoint:  (env.SH_S3_ENDPOINT  || "").replace(/\/$/, ""),
  bucket:    env.SH_S3_BUCKET    || "",
  region:    env.SH_S3_REGION    || "nbg1",
  accessKey: env.SH_S3_ACCESS_KEY || "",
  secretKey: env.SH_S3_SECRET_KEY || "",
});

export const EMPTY_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

export const s3Fetch = async (env, method, key, body = null, extraHeaders = {}) => {
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

export const presignedPutUrl = async (env, key, expiresIn) => {
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

export const presignedGetUrl = async (env, key, expiresIn) => {
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
