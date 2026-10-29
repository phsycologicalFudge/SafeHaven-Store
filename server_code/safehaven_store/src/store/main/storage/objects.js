import { apkKey, stagingKey, imageKey, IMAGE_SLOTS, ALLOWED_IMAGE_TYPES, MAX_IMAGE_BYTES } from "./constants.js";
import { cfg, s3Fetch } from "./s3.js";

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
