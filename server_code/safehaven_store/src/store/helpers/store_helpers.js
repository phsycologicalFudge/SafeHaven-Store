import { publicImageUrl } from "../storage.js";

export const nowUnix = () => Math.floor(Date.now() / 1000);

export const cryptoRandomHex = (bytes) => {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
};

export const COMMUNITY_DEVELOPER_ID = "safehaven-community";

export const normalizeStoreText = (value) => {
  if (value === null || value === undefined) return null;

  const clean = value
    .toString()
    .replace(/\\r\\n/g, "\n")
    .replace(/\\n/g, "\n")
    .replace(/\\t/g, " ")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/gi, "\"")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return clean || null;
};

export const parseScreenshots = (screenshotsJson) => {
  if (!screenshotsJson) return [];
  try { return JSON.parse(screenshotsJson); } catch { return []; }
};

const imageCacheTag = (env, app) => {
  const salt = (env.SH_IMAGE_VERSION || "").toString().trim();
  const ver  = Number(app.image_version) || 0;
  return salt ? `${salt}-${ver}` : String(ver);
};

const publicBase = (env) => (env.SH_PUBLIC_BASE || "").toString().trim().replace(/\/$/, "");

const versionedImageUrl = (env, app, key) => {
  const tag = encodeURIComponent(imageCacheTag(env, app));
  const base = publicBase(env);
  return base
    ? `${base}/store/img/${key}?v=${tag}`
    : `${publicImageUrl(env, key)}?v=${tag}`;
};

export const buildIndexAppEntry = (env, app) => ({
  packageName: app.package_name,
  name:        app.name,
  summary:     normalizeStoreText(app.summary),
  description: normalizeStoreText(app.description),
  repoUrl:     app.repo_url,
  trustLevel:  app.trust_level,
  category:    app.category || null,
  upstream:    app.upstream || null,
  iconUrl:     app.icon_key ? versionedImageUrl(env, app, app.icon_key) : null,
  screenshots: parseScreenshots(app.screenshots_json).map((k) => versionedImageUrl(env, app, k)),
});