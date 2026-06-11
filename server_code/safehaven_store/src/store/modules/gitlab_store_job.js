import { createSubmission, advanceSubmissionToScan, setAppImages } from "../store_db.js";
import { getPresignedStagingUploadUrl, addOrUpdateApp } from "../storage.js";
import { uploadImageFromUrl } from "./images/image_upload.js";
import {
  nowUnix,
  cryptoRandomHex,
  normalizeStoreText,
  parseScreenshots,
  buildIndexAppEntry,
  COMMUNITY_DEVELOPER_ID,
} from "../helpers/store_helpers.js";
import {
  findApkAsset,
  tagToVersionCode,
  versionNameToVersionCode,
  assetNameToVersionName,
  uploadBufferToStaging,
} from "../helpers/apk_helpers.js";

const MAX_APK_BYTES       = 100 * 1024 * 1024;
const ADMIN_MAX_APK_BYTES = 200 * 1024 * 1024;
const MAX_ICON_BYTES      = 4 * 1024 * 1024;

const GITLAB_API = "https://gitlab.com/api/v4";

const gitlabHeaders = (env) => {
  const token = (env.GITLAB_TOKEN || "").trim();
  return {
    "user-agent": "SafeHaven-Store/1.0",
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  };
};

export const normalizeGitLabRepoUrl = (repoUrl) => {
  const clean = (repoUrl || "").toString().trim().replace(/\.git$/, "").replace(/\/$/, "");
  const m = clean.match(/^https?:\/\/gitlab\.com\/([^/]+\/[^/]+(?:\/[^/]+)*)$/i);
  if (!m) return null;
  return `https://gitlab.com/${m[1]}`;
};

const encodedPath = (repoUrl) => {
  const url = normalizeGitLabRepoUrl(repoUrl);
  if (!url) return null;
  return encodeURIComponent(url.replace("https://gitlab.com/", ""));
};

const gitlabLatestRelease = async (env, repoUrl) => {
  const path = encodedPath(repoUrl);
  if (!path) return null;

  const res = await fetch(
    `${GITLAB_API}/projects/${path}/releases?per_page=1`,
    { headers: gitlabHeaders(env) }
  );

  if (res.status === 404) return null;
  if (!res.ok) return null;

  const data = await res.json();
  if (!Array.isArray(data) || !data.length) return null;

  const release = data[0];
  if (release.upcoming_release) return null;

  return release;
};

const gitlabReleaseAssets = (release) => {
  const links = release?.assets?.links || [];
  return links
    .filter((l) => l?.url && l?.name?.toLowerCase().endsWith(".apk"))
    .map((l) => ({
      name:                 l.name,
      browser_download_url: l.url,
      state:                "uploaded",
      size:                 l.size || 0,
    }));
};

const gitlabRepoDetails = async (env, repoUrl) => {
  const path = encodedPath(repoUrl);
  if (!path) return null;

  const res = await fetch(
    `${GITLAB_API}/projects/${path}`,
    { headers: gitlabHeaders(env) }
  );

  if (!res.ok) return null;

  const data = await res.json();

  return {
    name:        data.name || "",
    description: data.description || "",
    stars:       data.star_count || 0,
    topics:      Array.isArray(data.topics) ? data.topics : [],
    repoUrl:     normalizeGitLabRepoUrl(data.web_url || repoUrl) || repoUrl,
  };
};

const gitlabReadmeRaw = async (env, repoUrl) => {
  const path = encodedPath(repoUrl);
  if (!path) return null;

  const res = await fetch(
    `${GITLAB_API}/projects/${path}/repository/files/README.md/raw?ref=HEAD`,
    { headers: gitlabHeaders(env) }
  );

  if (!res.ok) return null;
  return await res.text() || null;
};

const getAppByRepoUrl = (env, repoUrl) => {
  const normal = normalizeGitLabRepoUrl(repoUrl);
  if (!normal) return null;
  return env.api_control_db
    .prepare("SELECT * FROM store_apps WHERE repo_url = ?1 LIMIT 1")
    .bind(normal)
    .first();
};

const getAppByPackage = (env, packageName) =>
  env.api_control_db
    .prepare("SELECT id FROM store_apps WHERE package_name = ?1 LIMIT 1")
    .bind(packageName)
    .first();

const getStoreAppById = (env, appId) =>
  env.api_control_db
    .prepare("SELECT * FROM store_apps WHERE id = ?1 LIMIT 1")
    .bind((appId || "").toString().trim())
    .first();

const deleteAppById = async (env, appId) => {
  const id = (appId || "").toString().trim();
  if (!id) return;
  await env.api_control_db.prepare("DELETE FROM store_submissions WHERE app_id = ?1").bind(id).run();
  await env.api_control_db
    .prepare("DELETE FROM store_apps WHERE id = ?1 AND developer_id = ?2 AND claimed = 0")
    .bind(id, COMMUNITY_DEVELOPER_ID)
    .run();
};

const makePlaceholderPackageName = (repoUrl) => {
  const clean = normalizeGitLabRepoUrl(repoUrl) || repoUrl;
  const parts = clean.replace("https://gitlab.com/", "").split("/");
  const norm = (s) => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "") || "x";
  return `pending.gitlab.${norm(parts[0])}.${norm(parts[1] || parts[0])}`;
};

const displayNameOf = (name, repoUrl) => {
  const fallback = (normalizeGitLabRepoUrl(repoUrl) || repoUrl).split("/").pop() || "Unknown App";
  return (name || fallback)
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();
};

const createUnclaimedStoreApp = async (env, { packageName, name, summary, description, repoUrl, category }) => {
  const now = nowUnix();

  const existing = await env.api_control_db
    .prepare("SELECT id, status FROM store_apps WHERE package_name = ?1 LIMIT 1")
    .bind(packageName)
    .first();

  if (existing) {
    if (existing.status !== "active") {
      await env.api_control_db
        .prepare("UPDATE store_apps SET name = ?2, summary = ?3, description = ?4, repo_url = ?5, status = 'active', auto_tracked = 1, updated_at = ?6 WHERE id = ?1")
        .bind(existing.id, name, summary, description, repoUrl, now)
        .run();
    }
    return existing.id;
  }

  const id        = cryptoRandomHex(16);
  const repoToken = cryptoRandomHex(24);

  await env.api_control_db
    .prepare(
      `INSERT INTO store_apps
        (id, developer_id, package_name, name, summary, description,
         repo_url, repo_token, repo_verified, trust_level, status,
         claimed, auto_tracked, created_at, updated_at, upstream)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, 'unverified', 'active', 0, 1, ?9, ?9, 'gitlab')`
    )
    .bind(id, COMMUNITY_DEVELOPER_ID, packageName, name, summary || null, description || null, repoUrl, repoToken, now)
    .run();

  return id;
};

const importCandidate = async (env, { repoUrl, adminImport = false }) => {
  const normalized = normalizeGitLabRepoUrl(repoUrl);
  if (!normalized) return { skipped: true, reason: "invalid_gitlab_url" };

  const existing = await getAppByRepoUrl(env, normalized);

  if (existing) {
    const autoTracked   = Number(existing.auto_tracked || 0) === 1;
    const claimed       = Number(existing.claimed || 0) === 1;
    const isPlaceholder = !existing.package_name || existing.package_name.startsWith("pending.");

    if (existing.status === "removed" && existing.developer_id === COMMUNITY_DEVELOPER_ID && autoTracked && !claimed) {
      await deleteAppById(env, existing.id);
    } else if (!isPlaceholder && existing.upstream !== "gitlab") {
      // different app sharing the same repo URL — not a conflict
    } else if (existing.upstream && existing.upstream !== "gitlab") {
      return { skipped: true, reason: `upstream_is_${existing.upstream}` };
    } else {
      return { skipped: true, reason: "already_tracked" };
    }
  }

  const release = await gitlabLatestRelease(env, normalized);
  if (!release) return { skipped: true, reason: "no_stable_release" };

  const rawAssets = gitlabReleaseAssets(release);
  const asset     = findApkAsset({ assets: rawAssets });
  if (!asset) return { skipped: true, reason: "no_matching_apk_asset" };

  const maxApkBytes = adminImport ? ADMIN_MAX_APK_BYTES : MAX_APK_BYTES;
  if (asset.size && asset.size > maxApkBytes) {
    return { skipped: true, reason: "apk_too_large", assetSize: asset.size, maxApkBytes };
  }

  const assetVersionName = assetNameToVersionName(asset.name);
  const versionName      = tagToVersionCode(release.tag_name) ? release.tag_name : assetVersionName;
  const versionCode      = tagToVersionCode(release.tag_name) || versionNameToVersionCode(assetVersionName);

  if (!versionName || !versionCode) {
    return { skipped: true, reason: "unparseable_version", releaseTag: release.tag_name, assetName: asset.name };
  }

  const packageName = makePlaceholderPackageName(normalized);
  const byPkg       = await getAppByPackage(env, packageName);
  if (byPkg) return { skipped: true, reason: "placeholder_collision" };

  const details = await gitlabRepoDetails(env, normalized);

  const summary     = normalizeStoreText((details?.description || "").slice(0, 200).trim()) || null;
  const description = summary;
  const name        = displayNameOf(details?.name, normalized);
  const category    = "other";

  const appId = await createUnclaimedStoreApp(env, { packageName, name, summary, description, repoUrl: normalized, category });
  if (!appId) return { skipped: true, reason: "app_create_failed" };

  let apkBuffer;
  try {
    const apkRes = await fetch(asset.browser_download_url, { headers: { "user-agent": "SafeHaven-Store/1.0" } });
    if (!apkRes.ok) {
      await deleteAppById(env, appId);
      return { skipped: true, reason: `apk_download_failed:${apkRes.status}` };
    }
    apkBuffer = await apkRes.arrayBuffer();
  } catch (e) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: `apk_download_error:${String(e?.message || e)}` };
  }

  if (apkBuffer.byteLength > maxApkBytes) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: "apk_too_large_post_download", assetSize: apkBuffer.byteLength, maxApkBytes };
  }

  try {
    await uploadBufferToStaging(env, packageName, versionCode, apkBuffer, getPresignedStagingUploadUrl);
  } catch (e) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: `staging_failed:${String(e?.message || e)}` };
  }

  const submissionId = await createSubmission(env, {
    appId,
    developerId: COMMUNITY_DEVELOPER_ID,
    packageName,
    versionName,
    versionCode,
    stagingKey: `staging/${packageName}/${versionCode}/app.apk`,
  });

  if (!submissionId) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: "submission_create_failed" };
  }

  await advanceSubmissionToScan(env, submissionId);

  return { imported: true, appId, submissionId, packageName, versionCode };
};

export const refreshGitLabMetadataForApp = async (env, app) => {
  const normalized = normalizeGitLabRepoUrl(app.repo_url);
  if (!normalized) return false;

  const details = await gitlabRepoDetails(env, normalized).catch(() => null);
  if (!details) return false;

  const summary     = normalizeStoreText((details.description || app.summary || "").slice(0, 200).trim()) || null;
  const description = normalizeStoreText(details.description || app.description || null);

  await env.api_control_db
    .prepare(
      `UPDATE store_apps
       SET summary = ?2, description = ?3, updated_at = ?4
       WHERE id = ?1 AND auto_tracked = 1 AND claimed = 0`
    )
    .bind(app.id, summary, description, nowUnix())
    .run();

  const updatedApp = await getStoreAppById(env, app.id);
  if (updatedApp) await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));

  return true;
};

export const pollGitLabApp = async (env, app) => {
  const normalized = normalizeGitLabRepoUrl(app.repo_url);
  if (!normalized) return null;

  await refreshGitLabMetadataForApp(env, app);

  const release = await gitlabLatestRelease(env, normalized);
  if (!release) return null;

  const rawAssets = gitlabReleaseAssets(release);
  const asset     = findApkAsset({ assets: rawAssets });
  if (!asset) return null;

  if (asset.size && asset.size > MAX_APK_BYTES) return null;

  const versionCode = tagToVersionCode(release.tag_name);
  if (!versionCode) return null;
  const versionName = release.tag_name;

  const existing = await env.api_control_db
    .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND version_code = ?2 LIMIT 1")
    .bind(app.id, versionCode)
    .first();
  if (existing) return null;

  if (Number(app.submission_mode_manual || 0) === 1) return null;

  const apkRes = await fetch(asset.browser_download_url, { headers: { "user-agent": "SafeHaven-Store/1.0" } });
  if (!apkRes.ok) throw new Error(`apk_download_failed:${apkRes.status}`);
  const apkBuffer = await apkRes.arrayBuffer();

  if (apkBuffer.byteLength > MAX_APK_BYTES) return null;

  await uploadBufferToStaging(env, app.package_name, versionCode, apkBuffer, getPresignedStagingUploadUrl);

  const submissionId = await createSubmission(env, {
    appId:       app.id,
    developerId: COMMUNITY_DEVELOPER_ID,
    packageName: app.package_name,
    versionName,
    versionCode,
    stagingKey:  `staging/${app.package_name}/${versionCode}/app.apk`,
  });

  if (!submissionId) throw new Error("submission_create_failed");
  await advanceSubmissionToScan(env, submissionId);

  return true;
};

export async function runGitLabDirectImport(env, input = {}) {
  const repoUrl = (input.repoUrl || "").toString().trim();
  if (!repoUrl) return { imported: false, skipped: true, reason: "repoUrl_required" };

  const outcome = await importCandidate(env, { repoUrl, adminImport: input.adminImport === true });

  console.log(JSON.stringify({ tag: "direct_gitlab_import", repoUrl, outcome }));

  return { repoUrl, ...outcome };
}