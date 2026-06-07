import {
  getStoreAppByPackage,
  getStoreAppById,
  getStoreAppsByDeveloper,
  getAllStoreApps,
  getAllLiveApps,
  createStoreApp,
  setAppRepoVerified,
  setAppSigningKeyHash,
  setAppTrustLevel,
  setAppStatus,
  setAppCategory,
  setAppImages,
  createSubmission,
  getSubmissionById,
  getSubmissionsByApp,
  getSubmissionsByDeveloper,
  getSubmissionsByStatus,
  advanceSubmissionToScan,
  markSubmissionScanning,
  recordScanResult,
  approveSubmission,
  rejectSubmission,
  cancelSubmission,
  getSubmissionsDueForAutoApproval,
  SUBMISSION_STATUS,
  APP_STATUS,
  TRUST_LEVEL,
} from "./store_db.js";

import {
  getIndex,
  putIndex,
  addOrUpdateApp,
  addVersionToApp,
  removeApp,
  getPresignedStagingUploadUrl,
  getPresignedDownloadUrl,
  getPresignedImageUploadUrl,
  publicImageUrl,
  headStagingObject,
  promoteStagingToProduction,
  putImageObject,
  deleteStagingApk,
  apkKey,
  stagingKey,
  imageKey,
  IMAGE_SLOTS,
  CATEGORIES,
  getChangelog,
  putIndexWithChangelog,
} from "./storage.js";

import { handleRatingsRoute, handleAdminRatingsRoute } from "./modules/ratings.js";
import { normaliseIcon } from "./modules/images/icon_normalise.js";
import { normaliseScreenshot } from "./modules/images/screenshot_normalise.js";
import { uploadImageFromBuffer } from "./modules/images/image_upload.js";
import { runGitHubBootstrapImport, runGitHubDirectImport, runGitHubReadmeSweep, refreshGitHubMetadataForApp } from "./modules/git_store_job.js";
import { runGitLabDirectImport, normalizeGitLabRepoUrl } from "./modules/gitlab_store_job.js";
import { runCodebergDirectImport, normalizeCodebergRepoUrl } from "./modules/codeberg_store_job.js";
import { runUpstreamPolls } from "./modules/upstream_orchestrator.js";
import { runFdroidSync, runFdroidUpdateCheck, importOrUpdateFdroidApp, runFdroidCronJob } from "./modules/fdroid_store_job.js";
import { nowUnix, cryptoRandomHex, normalizeStoreText, parseScreenshots, buildIndexAppEntry, COMMUNITY_DEVELOPER_ID } from "./helpers/store_helpers.js";
import { parseGitHubRepo, githubLatestRelease, normalizeAssetText, apkAssetsOf, scoreApkAsset, findApkAsset, tagToVersionCode, uploadBufferToStaging } from "./helpers/github_helpers.js";

export {
  runGitHubBootstrapImport,
  runGitHubDirectImport,
  runGitHubReadmeSweep,
  runGitLabDirectImport,
  runCodebergDirectImport,
  runFdroidSync,
  runFdroidUpdateCheck,
  runFdroidCronJob,
  runUpstreamPolls,
};

const corsHeaders = {
  "access-control-allow-origin":  "*",
  "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
  "access-control-allow-headers": "authorization,content-type,x-vps-auth",
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders },
  });

const readJson = async (req) => {
  const ct = req.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) return null;
  try { return await req.json(); } catch { return null; }
};

const unauthorized = () => json({ error: "unauthorized" }, 401);
const forbidden    = () => json({ error: "forbidden" }, 403);
const badRequest   = (msg = "bad_request") => json({ error: msg }, 400);
const notFound     = () => json({ error: "not_found" }, 404);

const isScannerAuth = (env, request) => {
  const provided = (request.headers.get("x-vps-auth") || "").trim();
  const secret   = (env.SH_SCANNER_SECRET || "").trim();
  return !!(provided && secret && provided === secret);
};

const REPO_VERIFY_FILE = ".safehaven";

const buildRawFileUrl = (repoUrl) => {
  const url = (repoUrl || "").toString().trim().replace(/\/$/, "").replace(/\.git$/, "");
  const gh  = url.match(/^https?:\/\/github\.com\/([^/]+\/[^/]+)$/);
  if (gh) return `https://raw.githubusercontent.com/${gh[1]}/HEAD/${REPO_VERIFY_FILE}`;
  const gl  = url.match(/^https?:\/\/gitlab\.com\/([^/]+\/[^/]+)$/);
  if (gl) return `https://gitlab.com/${gl[1]}/-/raw/HEAD/${REPO_VERIFY_FILE}`;
  const cb  = url.match(/^https?:\/\/codeberg\.org\/([^/]+\/[^/]+)$/);
  if (cb) return `https://codeberg.org/${cb[1]}/raw/branch/main/${REPO_VERIFY_FILE}`;
  return null;
};

const buildVersionEntry = (submission) => ({
  versionName: submission.version_name,
  versionCode: submission.version_code,
  apkPath:     submission.apk_key || apkKey(submission.package_name, submission.version_code),
  apkSize:     submission.apk_size   || null,
  sha256:      submission.apk_sha256 || null,
  scannedAt:   submission.scanned_at || null,
  added:       submission.submitted_at,
});

const approveAndPublish = async (env, submission, reviewedBy = null) => {
  const { id, version_code, app_id, staging_key } = submission;

  const app = await getStoreAppById(env, app_id);
  if (!app) throw new Error("app_not_found");

  const finalPackageName = (app.package_name || submission.package_name || "").toString().trim();
  if (!finalPackageName) throw new Error("package_name_missing");

  const prodKey = apkKey(finalPackageName, version_code);

  await promoteStagingToProduction(env, staging_key, prodKey);
  await approveSubmission(env, id, prodKey, reviewedBy);

  const updatedSubmission = {
    ...submission,
    package_name: finalPackageName,
    apk_key:      prodKey,
  };

  const updatedApp = await getStoreAppById(env, app_id);
  if (updatedApp) {
    await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
    await addVersionToApp(env, finalPackageName, buildVersionEntry(updatedSubmission));
  }
};

const setAppSigningFlag = async (env, appId, flag) => {
  await env.api_control_db
    .prepare("UPDATE store_apps SET signing_flag = ?2, updated_at = ?3 WHERE id = ?1")
    .bind((appId || "").toString().trim(), flag, nowUnix())
    .run();
};

const saveScannerIcon = async (env, appId, packageName, body) => {
  const iconBase64  = (body.iconBase64 || "").toString().trim();
  const contentType = (body.iconContentType || "").toString().trim().toLowerCase();

  if (!iconBase64) return;
  if (!["image/png", "image/jpeg", "image/webp"].includes(contentType)) return;

  let raw;
  try {
    const binary = atob(iconBase64);
    raw = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) raw[i] = binary.charCodeAt(i);
  } catch {
    return;
  }

  if (!raw.byteLength || raw.byteLength > 2 * 1024 * 1024) return;

  const app = await getStoreAppById(env, appId);
  if (app && app.icon_key) return;

  let bytes;
  try {
    bytes = await normaliseIcon(raw);
  } catch {
    bytes = raw;
  }

  const existingScreenshots = parseScreenshots(app?.screenshots_json);
  const iconKey = await putImageObject(env, packageName, "icon", bytes, "image/png");

  await setAppImages(env, appId, {
    iconKey,
    screenshotKeys: existingScreenshots,
  });
};

const getLiveSubmissionForRescan = async (env, packageName, versionCode) => {
  const pkg = (packageName || "").toString().trim();
  const vc  = Number(versionCode);

  if (!pkg || !Number.isFinite(vc)) return null;

  return env.api_control_db
    .prepare(
      `SELECT
         ss.*,
         sa.id AS app_id,
         sa.package_name AS app_package_name,
         sa.signing_key_hash AS stored_signing_key_hash,
         sa.auto_tracked AS app_auto_tracked
       FROM store_submissions ss
       JOIN store_apps sa ON sa.id = ss.app_id
       WHERE sa.package_name = ?1
         AND ss.version_code = ?2
         AND ss.status = 'live'
         AND sa.status = 'active'
       LIMIT 1`
    )
    .bind(pkg, vc)
    .first();
};

const recordRescanResult = async (env, submissionId, input) => {
  const clean      = (submissionId || "").toString().trim();
  const passed     = input.passed ? 1 : 0;
  const scanResult = typeof input.detail === "object" ? JSON.stringify(input.detail) : (input.detail || null);
  const apkSha256  = (input.apkSha256 || "").toString().trim() || null;
  const apkSize    = Number.isFinite(Number(input.apkSize)) ? Number(input.apkSize) : null;
  const scannedAt  = Number.isFinite(Number(input.scannedAt)) ? Number(input.scannedAt) : nowUnix();

  if (!clean) return null;

  await env.api_control_db
    .prepare(
      `UPDATE store_submissions
       SET scan_passed = ?2,
           scan_result = ?3,
           apk_sha256 = ?4,
           apk_size = ?5,
           scanned_at = ?6,
           updated_at = ?6
       WHERE id = ?1
         AND status = 'live'`
    )
    .bind(clean, passed, scanResult, apkSha256, apkSize, scannedAt)
    .run();

  return {
    apkSha256,
    apkSize,
    scannedAt,
  };
};

const createUnclaimedStoreApp = async (env, input) => {
  const packageName = (input.packageName || "").toString().trim();
  const name        = (input.name || "").toString().trim();
  const repoUrl     = (input.repoUrl || "").toString().trim();
  const summary     = normalizeStoreText(input.summary);
  const description = normalizeStoreText(input.description);
  const now         = nowUnix();
  if (!packageName || !name || !repoUrl) return null;

  const existing = await env.api_control_db
    .prepare("SELECT id, status FROM store_apps WHERE package_name = ?1 LIMIT 1")
    .bind(packageName)
    .first();

  if (existing) {
    if (existing.status !== APP_STATUS.ACTIVE) {
      await env.api_control_db
        .prepare(
          "UPDATE store_apps SET name = ?2, summary = ?3, description = ?4, repo_url = ?5, status = ?6, auto_tracked = 1, updated_at = ?7 WHERE id = ?1"
        )
        .bind(existing.id, name, summary, description, repoUrl, APP_STATUS.ACTIVE, now)
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
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, 'unverified', ?9, 0, 1, ?10, ?10, NULL)`
    )
    .bind(id, COMMUNITY_DEVELOPER_ID, packageName, name, summary, description, repoUrl, repoToken, APP_STATUS.ACTIVE, now)
    .run();
  return id;
};

const getAppsForRepoPolling = async (env, maxAgeSeconds = 21600) => {
  const cutoff = nowUnix() - maxAgeSeconds;
  const rows = await env.api_control_db
    .prepare(
      `SELECT * FROM store_apps
       WHERE auto_tracked = 1
         AND status = 'active'
         AND (upstream IS NULL OR upstream != 'fdroid')
         AND repo_url LIKE 'https://github.com/%'
         AND (last_repo_check IS NULL OR last_repo_check <= ?1)
       ORDER BY last_repo_check ASC
       LIMIT 50`
    )
    .bind(cutoff)
    .all();
  return rows.results || [];
};

const setAppLastRepoCheck = async (env, appId) => {
  await env.api_control_db
    .prepare("UPDATE store_apps SET last_repo_check = ?2 WHERE id = ?1")
    .bind((appId || "").toString().trim(), nowUnix())
    .run();
};

const setAppClaimed = async (env, appId, developerId) => {
  await env.api_control_db
    .prepare(
      "UPDATE store_apps SET claimed = 1, auto_tracked = 0, developer_id = ?2, trust_level = ?3, updated_at = ?4 WHERE id = ?1"
    )
    .bind((appId || "").toString().trim(), developerId, TRUST_LEVEL.VERIFIED_SOURCE, nowUnix())
    .run();
};

const getSubmissionByVersionCode = async (env, appId, versionCode) =>
  env.api_control_db
    .prepare("SELECT * FROM store_submissions WHERE app_id = ?1 AND version_code = ?2 LIMIT 1")
    .bind((appId || "").toString().trim(), versionCode)
    .first();

const deleteSubmissionById = async (env, submissionId) => {
  await env.api_control_db
    .prepare("DELETE FROM store_submissions WHERE id = ?1")
    .bind((submissionId || "").toString().trim())
    .run();
};


const MAX_APK_BYTES = 100 * 1024 * 1024;

const pollAppRepo = async (env, app) => {
  const gh = parseGitHubRepo(app.repo_url);
  if (!gh) { await setAppLastRepoCheck(env, app.id); return; }

  await refreshGitHubMetadataForApp(env, app, gh.owner, gh.repo);

  const release = await githubLatestRelease(env, gh.owner, gh.repo);
  await setAppLastRepoCheck(env, app.id);
  if (!release) return;

  const asset = findApkAsset(release);
  if (!asset) return;

  if (asset.size && asset.size > MAX_APK_BYTES) return;

  const versionCode = tagToVersionCode(release.tag_name);
  if (!versionCode) return;
  const versionName = release.tag_name;

  const existing = await getSubmissionByVersionCode(env, app.id, versionCode);
  if (existing) return;

  const apkRes = await fetch(asset.browser_download_url, {
    headers: { "user-agent": "SafeHaven-Store/1.0" },
  });
  if (!apkRes.ok) throw new Error(`apk_download_failed:${apkRes.status}`);
  const apkBuffer = await apkRes.arrayBuffer();

  if (apkBuffer.byteLength > MAX_APK_BYTES) return;

  await uploadBufferToStaging(env, app.package_name, versionCode, apkBuffer);

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

  console.log(JSON.stringify({
    tag:          "unclaimed_auto_update",
    appId:        app.id,
    packageName:  app.package_name,
    versionCode,
    submissionId,
  }));

  return true;
};

export async function runUnclaimedRepoPolls(env) {
  const apps    = await getAppsForRepoPolling(env);
  const results = { checked: 0, polled: 0, submitted: 0, errors: [] };
  for (const app of apps) {
    results.checked++;
    try {
      const queued = await pollAppRepo(env, app);
      results.polled++;
      if (queued) results.submitted++;
    } catch (e) {
      results.errors.push({ appId: app.id, error: String(e?.message || e) });
    }
  }
  return results;
}

export async function runStoreAutoApprovals(env) {
  const due = await getSubmissionsDueForAutoApproval(env);
  for (const submission of due) {
    try {
      await approveAndPublish(env, submission, null);
    } catch (e) {
      console.log(JSON.stringify({
        tag:           "auto_approval_failed",
        submission_id: submission.id,
        error:         String(e?.message || e),
      }));
    }
  }
  return due.length;
}

export async function handleStore(request, env, auth) {
  const url    = new URL(request.url);
  const path   = url.pathname;
  const method = request.method;

  const getAuthedUser = async () => {
    if (!auth || typeof auth.getUser !== "function") return null;
    return await auth.getUser(request, env);
  };

  const requireUser = async () => {
    const me = await getAuthedUser();
    return me || null;
  };

  const requireDeveloper = async () => {
    const me = await requireUser();
    if (!me) return null;
    if (!me.developerEnabled) return false;
    return me;
  };

  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {

    if (method === "GET" && path === "/store/sync") {
      const since = Number(url.searchParams.get("since") || 0);
      const now = nowUnix();
      const SEVEN_DAYS_SEC = 7 * 24 * 60 * 60;

      if (!since || now - since > SEVEN_DAYS_SEC) {
        return json({
          action: "full",
          url: "/store/index.json"
        });
      }

      let changelog;
      try {
        changelog = await getChangelog(env);
      } catch {
        changelog = { events: [] };
      }

      const finalUpdates = new Map();
      const finalRemoves = new Set();
      let latestTimestamp = since;

      for (const event of changelog.events) {
        if (event.timestamp > since) {
          latestTimestamp = Math.max(latestTimestamp, event.timestamp);
          
          for (const pkg of event.removes) {
            finalRemoves.add(pkg);
            finalUpdates.delete(pkg);
          }
          
          for (const app of event.updates) {
            finalUpdates.set(app.packageName, app);
            finalRemoves.delete(app.packageName);
          }
        }
      }

      return json({
        action: "patch",
        timestamp: latestTimestamp,
        updates: Array.from(finalUpdates.values()),
        removes: Array.from(finalRemoves)
      });
    }

    if (method === "GET" && path === "/store/index.json") {
      const index = await getIndex(env);
      const filtered = {
        ...index,
        apps: (index.apps || []).filter((a) => Array.isArray(a.versions) && a.versions.length > 0),
      };
      return new Response(JSON.stringify(filtered), {
        headers: {
          "content-type":  "application/json; charset=utf-8",
          "cache-control": "public, max-age=60",
          ...corsHeaders,
        },
      });
    }

    if (method === "GET" && path.startsWith("/store/catalog/")) {
      const packageName = decodeURIComponent(path.replace("/store/catalog/", "")).trim();
      if (!packageName) return notFound();
      const index = await getIndex(env);
      const app   = index.apps.find((a) => a.packageName === packageName);
      if (!app) return notFound();
      return json(app);
    }

    if (method === "GET" && path.match(/^\/store\/apps\/[^/]+\/download\/[^/]+$/)) {
      const parts       = path.replace("/store/apps/", "").split("/download/");
      const packageName = decodeURIComponent(parts[0] || "").trim();
      const versionCode = Number(parts[1] || "");
      if (!packageName || !Number.isFinite(versionCode)) return badRequest("invalid_params");
      const index = await getIndex(env);
      const app   = index.apps.find((a) => a.packageName === packageName);
      if (!app) return notFound();
      const version = (app.versions ?? []).find((v) => v.versionCode === versionCode);
      if (!version) return notFound();
      const dlUrl = await getPresignedDownloadUrl(env, version.apkPath, 300);
      return json({ url: dlUrl });
    }

    if (method === "GET" && path === "/store/categories") {
      return json({ categories: CATEGORIES });
    }

if (method === "POST" && path === "/admin/store/fdroid-index-chunk") {
  const provided = (request.headers.get("authorization") || "").trim();
  if (!provided || provided !== (env.SH_ADMIN_SECRET || "").trim()) return unauthorized();

  const body = await readJson(request);
  if (!body) return badRequest("json_required");

  const type = (body.type || "").toString().trim();

  if (type === "repo") {
    const repoData = body.data || {};
    const totalApps = Number(body.totalApps || 0);
    const totalChunks = Number(body.totalChunks || 0);

    await env.api_control_db
      .prepare("INSERT OR REPLACE INTO sync_state (key, value) VALUES (?1, ?2)")
      .bind(
        "fdroid_chunk_state",
        JSON.stringify({
          repo: repoData,
          totalApps,
          totalChunks,
          receivedChunks: [],
          processedApps: 0,
          startedAt: nowUnix(),
        })
      )
      .run();

    return json({ ok: true, message: `Ready to receive ${totalChunks} chunks with ${totalApps} apps` });
  }

  if (type === "apps") {
    const chunkIndex = Number(body.chunkIndex || 0);
    const apps = Array.isArray(body.apps) ? body.apps : [];
    const totalChunks = Number(body.totalChunks || 0);

    const stateRow = await env.api_control_db
      .prepare("SELECT value FROM sync_state WHERE key = ?1")
      .bind("fdroid_chunk_state")
      .first();

    if (!stateRow) return badRequest("repo_metadata_not_initialized");

    const state = JSON.parse(stateRow.value);

    if (state.receivedChunks.includes(chunkIndex)) {
      return json({ ok: true, skipped: true, message: `Chunk ${chunkIndex} already processed` });
    }

    let imported = 0;
    let updated = 0;
    let skipped = 0;
    const errors = [];

    for (const app of apps) {
      try {
        const outcome = await importOrUpdateFdroidApp(env, app);
        if (outcome.imported) {
          imported++;
          if (!outcome.isNew) updated++;
        } else if (outcome.skipped) {
          skipped++;
        }
      } catch (e) {
        errors.push({ packageName: app.packageName, error: String(e?.message || e) });
      }
    }

    state.receivedChunks.push(chunkIndex);
    state.processedApps += apps.length;

    await env.api_control_db
      .prepare("UPDATE sync_state SET value = ?1 WHERE key = ?2")
      .bind(JSON.stringify(state), "fdroid_chunk_state")
      .run();

    return json({
      ok: true,
      chunkIndex,
      appsReceived: apps.length,
      imported,
      updated,
      skipped,
      errors: errors.slice(0, 5),
      totalReceived: state.receivedChunks.length,
      totalChunks,
    });
  }

  return badRequest("invalid_chunk_type");
}

    if (method === "PUT" && path === "/admin/store/fdroid-index") {
      const provided = (request.headers.get("authorization") || "").trim();
      if (!provided || provided !== (env.SH_ADMIN_SECRET || "").trim()) return unauthorized();
      const body = await request.arrayBuffer();
      if (!body.byteLength) return badRequest("empty_body");
      await env.SH_BUCKET.put("fdroid/index-v1.json", body, {
        httpMetadata: { contentType: "application/json" },
      });
      return json({ ok: true });
    }

    if (method === "POST" && path === "/store/apps") {
      const me = await requireDeveloper();
      if (me === null) return unauthorized();
      if (me === false) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const packageName = (body.packageName || "").toString().trim();
      const name        = (body.name        || "").toString().trim();
      const repoUrl     = (body.repoUrl     || "").toString().trim();
      const summary     = normalizeStoreText(body.summary);
      const description = normalizeStoreText(body.description);

      if (!packageName) return badRequest("missing_packageName");
      if (!name)        return badRequest("missing_name");
      if (!repoUrl)     return badRequest("missing_repoUrl");

      if (!/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(packageName)) {
        return badRequest("invalid_packageName");
      }

      const existing = await getStoreAppByPackage(env, packageName);
      if (existing) {
        if (!existing.claimed && existing.auto_tracked) {
          return json({ error: "package_already_registered", claimable: true, appId: existing.id, repoToken: existing.repo_token }, 409);
        }
        return json({ error: "package_already_registered", claimable: false }, 409);
      }

      const result = await createStoreApp(env, {
        developerId: me.id, packageName, name, summary, description, repoUrl,
      });
      if (!result) return json({ error: "create_failed" }, 500);

      return json({ ok: true, appId: result.id, repoToken: result.repoToken }, 201);
    }

    if (method === "GET" && path === "/store/apps") {
      const me = await requireUser();
      if (!me) return unauthorized();
      const apps = await getStoreAppsByDeveloper(env, me.id);
      return json({ apps });
    }

    if (method === "GET" && path === "/internal/store/pending-scans") {
      if (!isScannerAuth(env, request)) return unauthorized();
      const submissions = await getSubmissionsByStatus(env, SUBMISSION_STATUS.PENDING_SCAN);
      const withUrls = await Promise.all(
        submissions.map(async (s) => {
          const app = await getStoreAppById(env, s.app_id);
          return {
            ...s,
            downloadUrl:          await getPresignedDownloadUrl(env, s.staging_key),
            autoTracked:          app ? !!app.auto_tracked : false,
            storedSigningKeyHash: app?.signing_key_hash || null,
          };
        })
      );
      return json({ submissions: withUrls });
    }

    if (method === "GET" && path === "/internal/store/rescan-targets") {
      if (!isScannerAuth(env, request)) return unauthorized();

      const liveApps = await getAllLiveApps(env);
      const targets = await Promise.all(
        liveApps
          .filter((row) => row.package_name && Number.isFinite(Number(row.version_code)))
          .map(async (row) => {
            const apkPath = row.apk_key || apkKey(row.package_name, row.version_code);

            return {
              packageName: row.package_name,
              versionName: row.version_name || null,
              versionCode: Number(row.version_code),
              apkPath,
              apkSize: row.apk_size || null,
              apkSha256: row.apk_sha256 || null,
              scannedAt: row.scanned_at || null,
              downloadUrl: await getPresignedDownloadUrl(env, apkPath),
            };
          })
      );

      return json({ targets });
    }

if (method === "POST" && path === "/internal/store/rescan-result") {
      if (!isScannerAuth(env, request)) return unauthorized();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const packageName = (body.packageName || "").toString().trim();
      const versionCode = Number(body.versionCode);

      if (!packageName) return badRequest("missing_packageName");
      if (!Number.isFinite(versionCode)) return badRequest("invalid_versionCode");

      const submission = await getLiveSubmissionForRescan(env, packageName, versionCode);
      if (!submission) return notFound();

      const realVersionCode = Number(body.manifestVersionCode);
      const realVersionName = body.manifestVersionName ? String(body.manifestVersionName).trim() : null;

      let finalVersionCode = submission.version_code;
      let finalVersionName = submission.version_name;
      let versionChanged = false;

      if (Number.isFinite(realVersionCode) && realVersionCode > 0 && realVersionCode !== submission.version_code) {
        const conflicting = await getSubmissionByVersionCode(env, submission.app_id, realVersionCode);
        if (!conflicting) {
          await env.api_control_db.prepare(
            "UPDATE store_submissions SET version_code = ?1, version_name = COALESCE(?2, version_name) WHERE id = ?3"
          ).bind(realVersionCode, realVersionName, submission.id).run();

          finalVersionCode = realVersionCode;
          if (realVersionName) finalVersionName = realVersionName;
          versionChanged = true;
        } else {
          const index = await getIndex(env);
          const idxApp = index?.apps?.find((a) => a.packageName === submission.package_name);
          if (idxApp?.versions) {
            const beforeLen = idxApp.versions.length;
            idxApp.versions = idxApp.versions.filter((v) => v.versionCode !== submission.version_code);
            if (idxApp.versions.length !== beforeLen) {
              await putIndexWithChangelog(env, index);
            }
          }
          await env.api_control_db
            .prepare("UPDATE store_submissions SET status = 'retired', updated_at = ?2 WHERE id = ?1")
            .bind(submission.id, nowUnix())
            .run();
          return json({ ok: true, retired: true });
        }
      }

      const update = await recordRescanResult(env, submission.id, {
        passed:    !!body.passed,
        detail:    body.detail    || null,
        apkSha256: body.apkSha256 || null,
        apkSize:   body.apkSize   || null,
        scannedAt: body.scannedAt || null,
      });

      const app = await getStoreAppById(env, submission.app_id);

      if (body.signingKeyHash && app && !app.signing_key_hash) {
        await setAppSigningKeyHash(env, app.id, body.signingKeyHash);
      }

      if (body.signingKeyHash && app && app.auto_tracked && app.signing_key_hash) {
        const observedKey = (body.signingKeyHash || "").toString().trim().toLowerCase();
        const storedKey   = (app.signing_key_hash || "").toString().trim().toLowerCase();

        if (observedKey && storedKey && observedKey !== storedKey) {
          await setAppSigningFlag(env, app.id, "signing_key_changed");
        }
      }

      if (app) {
        await saveScannerIcon(env, app.id, app.package_name, body);

        const updatedApp = await getStoreAppById(env, app.id);
        if (updatedApp && updatedApp.status === APP_STATUS.ACTIVE) {
          
          if (versionChanged) {
            const index = await getIndex(env);
            const idxApp = index.apps.find((a) => a.packageName === updatedApp.package_name);
            if (idxApp && idxApp.versions) {
              idxApp.versions = idxApp.versions.filter((v) => v.versionCode !== submission.version_code);
              await putIndexWithChangelog(env, index);
            }
          }

          await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
          await addVersionToApp(env, updatedApp.package_name, buildVersionEntry({
            ...submission,
            package_name: updatedApp.package_name,
            version_code: finalVersionCode,
            version_name: finalVersionName,
            apk_sha256: update?.apkSha256,
            apk_size: update?.apkSize,
            scanned_at: update?.scannedAt,
          }));
        }
      }

      return json({ ok: true });
    }

    if (method === "GET" && path.match(/^\/store\/apps\/[^/]+$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();
      if (app.developer_id !== me.id && !me.admin) return forbidden();
      const submissions = await getSubmissionsByApp(env, appId);
      return json({ app, submissions });
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/verify-repo$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/verify-repo", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                       return notFound();
      if (app.developer_id !== me.id) return forbidden();

      const rawUrl = buildRawFileUrl(app.repo_url);
      if (!rawUrl) return badRequest("unsupported_repo_host");

      let remoteContent;
      try {
        const res = await fetch(rawUrl, { headers: { "user-agent": "SafeHaven-Verifier/1.0" } });
        if (!res.ok) return json({ ok: false, reason: "file_not_found" }, 422);
        remoteContent = (await res.text()).trim();
      } catch {
        return json({ ok: false, reason: "fetch_failed" }, 422);
      }

      if (remoteContent !== (app.repo_token || "").trim()) {
        return json({ ok: false, reason: "token_mismatch" }, 422);
      }

      await setAppRepoVerified(env, appId, true);
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/submit$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/submit", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                             return notFound();
      if (app.developer_id !== me.id)       return forbidden();
      if (!app.repo_verified)               return json({ error: "repo_not_verified" }, 403);
      if (app.status !== APP_STATUS.ACTIVE) return json({ error: "app_not_active" }, 403);

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const versionName = (body.versionName || "").toString().trim();
      const versionCode = Number(body.versionCode);

      if (!versionName)                                      return badRequest("missing_versionName");
      if (!Number.isFinite(versionCode) || versionCode < 1) return badRequest("invalid_versionCode");

      const existingSubmissions = await getSubmissionsByApp(env, appId);
      const existingVersion     = existingSubmissions.find((s) => Number(s.version_code) === versionCode);

      if (existingVersion) {
        if (existingVersion.status === SUBMISSION_STATUS.PENDING_UPLOAD) {
          const uploadUrl = await getPresignedStagingUploadUrl(env, app.package_name, versionCode);
          return json({ ok: true, resumed: true, submissionId: existingVersion.id, uploadUrl }, 200);
        }
        return json({
          error:        "version_code_already_submitted",
          submissionId: existingVersion.id,
          status:       existingVersion.status,
        }, 409);
      }

      const submissionId = await createSubmission(env, {
        appId,
        developerId: me.id,
        packageName: app.package_name,
        versionName,
        versionCode,
        stagingKey:  stagingKey(app.package_name, versionCode),
      });
      if (!submissionId) return json({ error: "submission_failed" }, 500);

      const uploadUrl = await getPresignedStagingUploadUrl(env, app.package_name, versionCode);
      return json({ ok: true, submissionId, uploadUrl }, 201);
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/image-upload-urls$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/image-upload-urls", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                       return notFound();
      if (app.developer_id !== me.id && app.developer_id !== COMMUNITY_DEVELOPER_ID && !me.admin) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const requestedSlots = Array.isArray(body.slots) ? body.slots : [];
      const validSlots     = requestedSlots.filter((s) => IMAGE_SLOTS.includes(s));
      if (!validSlots.length) return badRequest("no_valid_slots");

      const urls = {};
      for (const slot of validSlots) {
        urls[slot] = await getPresignedImageUploadUrl(env, app.package_name, slot);
      }
      return json({ ok: true, urls });
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/images$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/images", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                       return notFound();
      if (app.developer_id !== me.id && app.developer_id !== COMMUNITY_DEVELOPER_ID && !me.admin) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const iconUploaded    = !!body.iconUploaded;
      const screenshotSlots = Array.isArray(body.screenshotSlots)
        ? body.screenshotSlots.map(Number).filter((n) => Number.isInteger(n) && n >= 1 && n <= 6)
        : [];

      const newIconKey          = iconUploaded ? imageKey(app.package_name, "icon") : (app.icon_key || null);
      const existingScreenshots = parseScreenshots(app.screenshots_json);
      const newScreenshotKeys   = screenshotSlots.length
        ? screenshotSlots.map((n) => imageKey(app.package_name, `screenshot_${n}`))
        : existingScreenshots;

      await setAppImages(env, appId, { iconKey: newIconKey, screenshotKeys: newScreenshotKeys });

      const updatedApp = await getStoreAppById(env, appId);
      if (updatedApp && updatedApp.status === APP_STATUS.ACTIVE) {
        const liveSubmission = await env.api_control_db
          .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND status = 'live' LIMIT 1")
          .bind(appId)
          .first();
        if (liveSubmission) {
          await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
        }
      }
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/upload-image$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/upload-image", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                                                                         return notFound();
      if (app.developer_id !== me.id && !me.admin)                                     return forbidden();

      const slot        = (url.searchParams.get("slot") || "").trim();
      const validSlots  = ["icon", "screenshot_1", "screenshot_2", "screenshot_3", "screenshot_4", "screenshot_5", "screenshot_6"];
      if (!validSlots.includes(slot))                                                   return badRequest("invalid_slot");

      const contentType = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      if (!["image/png", "image/jpeg", "image/webp"].includes(contentType))            return badRequest("invalid_content_type");

      const buffer = await request.arrayBuffer();
      if (!buffer.byteLength)                                                           return badRequest("empty_body");
      if (buffer.byteLength > 2 * 1024 * 1024)                                         return badRequest("image_too_large");

      const key = await uploadImageFromBuffer(env, app.package_name, slot, buffer);
      if (!key) return json({ error: "upload_failed" }, 500);

      const existingScreenshots = parseScreenshots(app.screenshots_json);
      const isIcon              = slot === "icon";
      const newIconKey          = isIcon ? key : (app.icon_key || null);
      const newScreenshotKeys   = isIcon
        ? existingScreenshots
        : (() => {
            const updated = [...existingScreenshots];
            const idx     = parseInt(slot.replace("screenshot_", ""), 10) - 1;
            updated[idx]  = key;
            return updated.filter(Boolean);
          })();

      await setAppImages(env, appId, { iconKey: newIconKey, screenshotKeys: newScreenshotKeys });

      const updatedApp = await getStoreAppById(env, appId);
      if (updatedApp && updatedApp.status === APP_STATUS.ACTIVE) {
        const liveSubmission = await env.api_control_db
          .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND status = 'live' LIMIT 1")
          .bind(appId)
          .first();
        if (liveSubmission) await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
      }

      return json({ ok: true, key });
    }

    if (method === "DELETE" && path.match(/^\/store\/submissions\/[^/]+$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const submissionId = path.replace("/store/submissions/", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      if (submission.developer_id !== me.id) return forbidden();
      if (submission.status !== SUBMISSION_STATUS.PENDING_UPLOAD) return json({ error: "not_cancellable" }, 409);
      await cancelSubmission(env, submissionId);
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/store\/submissions\/[^/]+\/confirm-upload$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const submissionId = path.replace("/store/submissions/", "").replace("/confirm-upload", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission)                       return notFound();
      if (submission.developer_id !== me.id) return forbidden();
      if (submission.status !== SUBMISSION_STATUS.PENDING_UPLOAD) {
        return json({ error: "invalid_status" }, 409);
      }

      const stagingCheck = await headStagingObject(env, submission.package_name, submission.version_code);
      if (!stagingCheck.ok) return json({ error: "staging_object_not_found" }, 422);

      await advanceSubmissionToScan(env, submissionId);
      return json({ ok: true });
    }

    if (method === "GET" && path.match(/^\/store\/submissions\/[^/]+$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const submissionId = path.replace("/store/submissions/", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      if (submission.developer_id !== me.id && !me.admin) return forbidden();
      return json({ submission });
    }

    if (method === "POST" && path === "/internal/store/scan-result") {
      if (!isScannerAuth(env, request)) return unauthorized();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const submissionId = (body.submissionId || "").toString().trim();
      if (!submissionId) return badRequest("missing_submissionId");

      const submission = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();

      if (
        submission.status !== SUBMISSION_STATUS.PENDING_SCAN &&
        submission.status !== SUBMISSION_STATUS.SCANNING
      ) {
        return json({ error: "invalid_status" }, 409);
      }

      await markSubmissionScanning(env, submissionId);
      await recordScanResult(env, submissionId, {
        passed:    !!body.passed,
        detail:    body.detail    || null,
        apkSha256: body.apkSha256 || null,
        apkSize:   body.apkSize   || null,
      });

      if (body.signingKeyHash) {
        const app = await getStoreAppById(env, submission.app_id);
        if (app && !app.signing_key_hash) {
          await setAppSigningKeyHash(env, submission.app_id, body.signingKeyHash);
        }
        if (app && app.auto_tracked && !body.passed) {
          const detail = body.detail || {};
          if (detail.verdict === "signing_key_changed") {
            await setAppSigningFlag(env, submission.app_id, "signing_key_changed");
          }
        }
      }

      const realVersionCode = Number(body.manifestVersionCode);
      const realVersionName = body.manifestVersionName ? String(body.manifestVersionName).trim() : null;

      if (body.apkSha256) {
        const sha256Dupe = await env.api_control_db
          .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND apk_sha256 = ?2 AND status = 'live' AND id != ?3 LIMIT 1")
          .bind(submission.app_id, body.apkSha256, submissionId)
          .first();
        if (sha256Dupe) {
          await rejectSubmission(env, submissionId, "duplicate_apk_sha256", null);
          return json({ ok: true, deduplicated: true });
        }
      }

      if (Number.isFinite(realVersionCode) && realVersionCode > 0) {
        if (realVersionCode !== Number(submission.version_code)) {
          const conflicting = await getSubmissionByVersionCode(env, submission.app_id, realVersionCode);
          if (conflicting) {
            await rejectSubmission(env, submissionId, "duplicate_version_code", null);
            return json({ ok: true, deduplicated: true });
          }
        }

        await env.api_control_db.prepare(
          "UPDATE store_submissions SET version_code = ?1, version_name = COALESCE(?2, version_name) WHERE id = ?3"
        ).bind(realVersionCode, realVersionName, submissionId).run();

        submission.version_code = realVersionCode;
        if (realVersionName) {
          submission.version_name = realVersionName;
        }
      }

      {
        const observedPkg = (body.packageName || "").toString().trim();
        const appForPkg   = await getStoreAppById(env, submission.app_id);

        if (appForPkg) {
          let finalPackageName = (appForPkg.package_name || "").toString().trim();

          if (observedPkg) {
            const isPlaceholder = !finalPackageName || finalPackageName.startsWith("pending.");

            if (isPlaceholder) {
              await env.api_control_db
                .prepare("UPDATE store_apps SET package_name = ?2, updated_at = ?3 WHERE id = ?1")
                .bind(appForPkg.id, observedPkg, nowUnix())
                .run();

              finalPackageName = observedPkg;
            } else if (finalPackageName && observedPkg !== finalPackageName) {
              await rejectSubmission(env, submissionId, "package_name_mismatch", null);

              return json({
                ok: false,
                error: "package_name_mismatch",
                expectedPackageName: finalPackageName,
                observedPackageName: observedPkg,
              }, 409);
            }
          }

          if (finalPackageName) {
            await saveScannerIcon(env, submission.app_id, finalPackageName, body);
          }
        }
      }

      return json({ ok: true });
    }

    if (method === "GET" && path === "/admin/store/submissions") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const statusFilter = url.searchParams.get("status") || SUBMISSION_STATUS.PENDING_REVIEW;
      const submissions  = await getSubmissionsByStatus(env, statusFilter);
      return json({ submissions });
    }

    if (method === "GET" && path === "/admin/store/apps") {
      const me = await requireUser();
      if (!me)       return unauthorized();
      if (!me.admin) return forbidden();
      const apps = await getAllStoreApps(env);
      return json({ apps });
    }

    if (method === "POST" && path === "/admin/store/clear-index") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      await putIndex(env, {
        version: 1,
        timestamp: nowUnix(),
        categories: CATEGORIES,
        apps: [],
      });

      return json({ ok: true, cleared: true });
    }

    if (method === "POST" && path === "/admin/store/bootstrap-import") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runGitHubBootstrapImport(env);
      return json({ ok: true, result });
    }

    if (method === "POST" && path === "/admin/store/fdroid-sync") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runFdroidSync(env);
      return json({ ok: true, result });
    }

    if (method === "POST" && path === "/admin/store/fdroid-update-check") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runFdroidUpdateCheck(env);
      return json({ ok: true, result });
    }

    if (method === "POST" && path === "/admin/store/readme-sweep") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const body = await readJson(request);
      const rawLimit = Number(body?.limit ?? 50);
      const limit = Number.isFinite(rawLimit)
        ? Math.max(1, Math.min(Math.floor(rawLimit), 100))
        : 100;

      const result = await runGitHubReadmeSweep(env, limit);
      return json({ ok: true, result });
    }

    if (method === "POST" && path === "/admin/store/import-repo") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const repoUrl = (body.repoUrl || "").toString().trim();
      if (!repoUrl) return badRequest("repoUrl_required");

      const urlLower   = repoUrl.toLowerCase();
      const isGitLab   = urlLower.includes("gitlab.com");
      const isCodeberg = urlLower.includes("codeberg.org");

      let result;
      if (isGitLab) {
        result = await runGitLabDirectImport(env, { repoUrl, adminImport: true });
      } else if (isCodeberg) {
        result = await runCodebergDirectImport(env, { repoUrl, adminImport: true });
      } else {
        result = await runGitHubDirectImport(env, {
          repoUrl,
          name:         body.name,
          summary:      body.summary,
          description:  body.description,
          iconUrl:      body.iconUrl,
          assetMatch:   body.assetMatch,
          preferredAbi: body.preferredAbi || "arm64-v8a",
          adminImport:  true,
        });
      }

      if (result?.skipped && !result?.imported) {
        return json({ ok: false, result }, 422);
      }

      return json({ ok: true, result }, 201);
    }

    if (method === "POST" && path === "/admin/store/upstream-poll") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runUpstreamPolls(env);
      return json({ ok: true, result });
    }

    if (method === "POST" && path.match(/^\/admin\/store\/submissions\/[^/]+\/approve$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const submissionId = path.replace("/admin/store/submissions/", "").replace("/approve", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      if (submission.status !== SUBMISSION_STATUS.PENDING_REVIEW) {
        return json({ error: "invalid_status" }, 409);
      }
      await approveAndPublish(env, submission, me.id);
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/admin\/store\/submissions\/[^/]+\/reject$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const submissionId = path.replace("/admin/store/submissions/", "").replace("/reject", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      const body   = await readJson(request);
      const reason = (body?.reason || "").toString().trim() || null;
      await rejectSubmission(env, submissionId, reason, me.id);
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/admin\/store\/apps\/[^/]+\/trust-level$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const appId      = path.replace("/admin/store/apps/", "").replace("/trust-level", "").trim();
      const body       = await readJson(request);
      if (!body) return badRequest("json_required");
      const trustLevel = body.trustLevel === null
        ? null
        : (body.trustLevel || "").toString().trim();

      if (trustLevel !== null && !Object.values(TRUST_LEVEL).includes(trustLevel)) {
        return badRequest("invalid_trustLevel");
      }
      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();
      await setAppTrustLevel(env, appId, trustLevel);
      if (app.status === APP_STATUS.ACTIVE) {
        await addOrUpdateApp(env, { ...buildIndexAppEntry(env, app), trustLevel });
      }
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/admin\/store\/apps\/[^/]+\/status$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const appId = path.replace("/admin/store/apps/", "").replace("/status", "").trim();
      const body  = await readJson(request);
      if (!body) return badRequest("json_required");

      const status = (body.status || "").toString().trim();
      if (!Object.values(APP_STATUS).includes(status)) return badRequest("invalid_status");

      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();

      if (status === APP_STATUS.REMOVED) {
        await removeApp(env, app.package_name);

        await env.api_control_db
          .prepare("DELETE FROM store_submissions WHERE app_id = ?1")
          .bind(appId)
          .run();

        await env.api_control_db
          .prepare("DELETE FROM store_apps WHERE id = ?1")
          .bind(appId)
          .run();

        return json({ ok: true, removed: true });
      }

      await setAppStatus(env, appId, status);

      if (status === APP_STATUS.SUSPENDED) {
        await removeApp(env, app.package_name);
      }

      if (status === APP_STATUS.ACTIVE) {
        const updatedApp = await getStoreAppById(env, appId);
        if (updatedApp) {
          const liveSubmission = await env.api_control_db
            .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND status = 'live' LIMIT 1")
            .bind(appId)
            .first();
          if (liveSubmission) {
            await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
          }
        }
      }

      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/category$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/category", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();
      if (app.developer_id !== me.id) return forbidden();
      const body = await readJson(request);
      if (!body) return badRequest("json_required");
      const category = (body.category || "").toString().trim() || null;
      if (category && !Object.keys(CATEGORIES).includes(category)) return badRequest("invalid_category");
      await setAppCategory(env, appId, category);
      if (app.status === APP_STATUS.ACTIVE) {
        await addOrUpdateApp(env, { ...buildIndexAppEntry(env, app), category });
      }
      return json({ ok: true });
    }

    if (method === "POST" && path.match(/^\/store\/apps\/[^/]+\/submission-mode$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/submission-mode", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();
      if (app.developer_id !== me.id) return forbidden();
      const body = await readJson(request);
      if (!body) return badRequest("json_required");
      const manual = body.manual === true ? 1 : 0;
      await env.api_control_db
        .prepare("UPDATE store_apps SET submission_mode_manual = ?2, updated_at = ?3 WHERE id = ?1")
        .bind(appId, manual, nowUnix())
        .run();
      return json({ ok: true, manual: manual === 1 });
    }

    if (method === "POST" && path.match(/^\/admin\/store\/apps\/[^/]+\/category$/)) {
      const me = await requireUser();
      if (!me)       return unauthorized();
      if (!me.admin) return forbidden();
      const appId    = path.replace("/admin/store/apps/", "").replace("/category", "").trim();
      const body     = await readJson(request);
      if (!body) return badRequest("json_required");
      const category = (body.category || "").toString().trim() || null;
      if (category && !Object.keys(CATEGORIES).includes(category)) return badRequest("invalid_category");
      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();
      await setAppCategory(env, appId, category);
      if (app.status === APP_STATUS.ACTIVE) {
        await addOrUpdateApp(env, { ...buildIndexAppEntry(env, app), category });
      }
      return json({ ok: true });
    }

    if (method === "POST" && path === "/store/track") {
      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const repoUrl  = (body.repoUrl || "").toString().trim();
      if (!repoUrl) return badRequest("repoUrl_required");

      const urlLower   = repoUrl.toLowerCase();
      const isGitHub   = urlLower.includes("github.com");
      const isGitLab   = urlLower.includes("gitlab.com");
      const isCodeberg = urlLower.includes("codeberg.org");

      if (!isGitHub && !isGitLab && !isCodeberg) {
        return badRequest("unsupported_platform");
      }

      if (isGitLab || isCodeberg) {
        const outcome = isGitLab
          ? await runGitLabDirectImport(env, { repoUrl })
          : await runCodebergDirectImport(env, { repoUrl });

        if (outcome.imported) {
          return json({
            ok:           true,
            appId:        outcome.appId,
            submissionId: outcome.submissionId,
            packageName:  outcome.packageName,
            versionCode:  outcome.versionCode,
          }, 201);
        }

        const reasonMap = {
          already_tracked:             [409, "already_tracked"],
          placeholder_collision:       [409, "already_tracked"],
          no_stable_release:           [422, "no_stable_release_found"],
          no_matching_apk_asset:       [422, "no_apk_asset_in_release"],
          apk_too_large:               [422, "apk_too_large"],
          apk_too_large_post_download: [422, "apk_too_large"],
          invalid_gitlab_url:          [400, "invalid_repo_url"],
          invalid_codeberg_url:        [400, "invalid_repo_url"],
          unparseable_version:         [422, "unsupported_release_tag"],
        };

        const [status, error] = reasonMap[outcome.reason] || [422, outcome.reason || "import_failed"];
        return json({ error, reason: outcome.reason }, status);
      }

      const summary     = normalizeStoreText(body.summary);
      const description = normalizeStoreText(body.description);
      const category    = (body.category || "").toString().trim() || null;

      const gh = parseGitHubRepo(repoUrl);
      if (!gh) return badRequest("invalid_repo_url");

      const name        = (body.name        || "").toString().trim() || gh.repo;
      const packageName = (body.packageName || "").toString().trim() || `pending.${gh.owner}.${gh.repo}`;

      let release;
      try {
        release = await githubLatestRelease(env, gh.owner, gh.repo);
      } catch (e) {
        return json({ error: "github_fetch_failed", detail: String(e?.message || e) }, 502);
      }
      if (!release) return json({ error: "no_stable_release_found" }, 422);

      const asset = findApkAsset(release);
      if (!asset) return json({ error: "no_apk_asset_in_release" }, 422);

      if (asset.size && asset.size > MAX_APK_BYTES) return json({ error: "apk_too_large" }, 422);

      const versionName = release.tag_name;
      const versionCode = tagToVersionCode(release.tag_name);
      if (!versionCode) return json({ error: "unsupported_release_tag", tag: release.tag_name }, 422);

      const existing = await getStoreAppByPackage(env, packageName);
      let appId = existing?.id || null;

      if (!appId) {
        appId = await createUnclaimedStoreApp(env, { packageName, name, summary, description, repoUrl });
        if (!appId) return json({ error: "app_create_failed" }, 500);
        try {
          const newApp = await getStoreAppById(env, appId);
          if (newApp) await refreshGitHubMetadataForApp(env, newApp, gh.owner, gh.repo);
        } catch {}
      } else if (existing.status !== APP_STATUS.ACTIVE) {
        await setAppStatus(env, appId, APP_STATUS.ACTIVE);
      }

      const existingSubmission = await getSubmissionByVersionCode(env, appId, versionCode);
      if (existingSubmission) {
        if (existingSubmission.status === "live") {
          return json({ error: "already_live", appId, submissionId: existingSubmission.id, versionName, versionCode }, 409);
        }

        const pendingStatuses = ["pending_upload", "pending_scan", "scanning", "pending_review"];
        if (pendingStatuses.includes(existingSubmission.status)) {
          return json({ error: "already_pending", appId, submissionId: existingSubmission.id, versionName, versionCode }, 409);
        }

        await deleteStagingApk(env, packageName, versionCode).catch(() => {});
        await deleteSubmissionById(env, existingSubmission.id);
      }

      let apkBuffer;
      try {
        const apkRes = await fetch(asset.browser_download_url, {
          headers: { "user-agent": "SafeHaven-Store/1.0" },
        });
        if (!apkRes.ok) throw new Error(`apk_download_failed:${apkRes.status}`);
        apkBuffer = await apkRes.arrayBuffer();
      } catch (e) {
        return json({ error: "apk_download_failed", detail: String(e?.message || e) }, 502);
      }

      if (apkBuffer.byteLength > MAX_APK_BYTES) return json({ error: "apk_too_large" }, 422);

      if (category) await setAppCategory(env, appId, category);

      try {
        await uploadBufferToStaging(env, packageName, versionCode, apkBuffer);
      } catch (e) {
        return json({ error: "staging_upload_failed", detail: String(e?.message || e) }, 500);
      }

      const submissionId = await createSubmission(env, {
        appId,
        developerId: COMMUNITY_DEVELOPER_ID,
        packageName,
        versionName,
        versionCode,
        stagingKey:  `staging/${packageName}/${versionCode}/app.apk`,
      });
      if (!submissionId) return json({ error: "submission_create_failed" }, 500);

      await advanceSubmissionToScan(env, submissionId);
      await setAppLastRepoCheck(env, appId);

      return json({ ok: true, appId, submissionId, versionName, versionCode }, 201);
    }

    if (method === "GET" && path.startsWith("/store/track/")) {
      const packageName = decodeURIComponent(path.replace("/store/track/", "")).trim();
      if (!packageName) return notFound();
      const app = await getStoreAppByPackage(env, packageName);
      if (!app) return notFound();
      return json({
        appId:         app.id,
        packageName:   app.package_name,
        name:          app.name,
        repoUrl:       app.repo_url,
        claimed:       !!app.claimed,
        trustLevel:    app.trust_level,
        signingFlag:   app.signing_flag || null,
        lastRepoCheck: app.last_repo_check || null,
        upstream:      app.upstream || null,
      });
    }

    if (method === "POST" && path.match(/^\/store\/track\/[^/]+\/claim$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.developerEnabled) return forbidden();

      const appId = path.replace("/store/track/", "").replace("/claim", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();

      const isFdroid = app.upstream === "fdroid";

      if (app.claimed && !isFdroid) return json({ error: "already_claimed" }, 409);

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const providedHash = (body.signingKeyHash || "").toString().trim();

      if (isFdroid) {
        if (!providedHash) return badRequest("signingKeyHash_required");
      }

      const gh = parseGitHubRepo(app.repo_url);
      if (!gh) return json({ error: "repo_not_verifiable" }, 422);

      const challengeRes = await fetch(
        `https://raw.githubusercontent.com/${gh.owner}/${gh.repo}/HEAD/.safehaven`,
        { headers: { "user-agent": "SafeHaven-Store/1.0" } }
      );
      if (!challengeRes.ok) return json({ error: "challenge_file_not_found" }, 403);
      const challengeBody = (await challengeRes.text()).trim();
      if (challengeBody !== app.repo_token) return json({ error: "challenge_mismatch" }, 403);

      await setAppClaimed(env, appId, me.id);
      await setAppRepoVerified(env, appId, true);

      if (isFdroid) {
        await setAppSigningKeyHash(env, appId, providedHash);
        await env.api_control_db.prepare("DELETE FROM store_submissions WHERE app_id = ?1").bind(appId).run();
        await env.api_control_db.prepare("UPDATE store_apps SET upstream = NULL WHERE id = ?1").bind(appId).run();

        const index = await getIndex(env);
        const idxApp = index.apps.find(a => a.packageName === app.package_name);
        if (idxApp) {
          idxApp.versions = [];
          idxApp.upstream = null;
          await putIndexWithChangelog(env, index);
        }
      }

      return json({ ok: true, claimed: true });
    }

    if (method === "POST" && path.match(/^\/admin\/store\/apps\/[^/]+\/override-hash$/)) {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const appId = path.replace("/admin/store/apps/", "").replace("/override-hash", "").trim();
      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const newHash = (body.newHash || "").toString().trim();
      const reason = (body.reason || "").toString().trim();

      if (!newHash) return badRequest("newHash_required");

      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();

      const oldHash = app.signing_key_hash || "";

      await setAppSigningKeyHash(env, appId, newHash);
      await env.api_control_db.prepare("UPDATE store_apps SET signing_flag = NULL WHERE id = ?1").bind(appId).run();
      await env.api_control_db.prepare(
        "INSERT INTO store_hash_history (app_id, old_hash, new_hash, reason, updated_by, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
      ).bind(appId, oldHash, newHash, reason, me.id, nowUnix()).run();

      return json({ ok: true, oldHash, newHash });
    }

if (method === "POST" && path === "/admin/store/normalise-images") {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const body   = await readJson(request).catch(() => null) || {};
      const offset = Math.max(0, Number(body.offset) || 0);

      const DEADLINE_MS = 25_000;
      const startedAt  = Date.now();

      const apps = await getAllStoreApps(env);

      const results = {
        icons:            { processed: 0, skipped: 0, failed: 0 },
        screenshots:      { processed: 0, skipped: 0, failed: 0 },
        errors:           [],
        totalIcons:       { processed: Number(body.totalIcons?.processed       || 0), skipped: Number(body.totalIcons?.skipped       || 0), failed: Number(body.totalIcons?.failed       || 0) },
        totalScreenshots: { processed: Number(body.totalScreenshots?.processed || 0), skipped: Number(body.totalScreenshots?.skipped || 0), failed: Number(body.totalScreenshots?.failed || 0) },
        offset:           null,
        appsTotal:        apps.length,
        appsChecked:      0,
      };

      for (let i = offset; i < apps.length; i++) {
        if (Date.now() - startedAt >= DEADLINE_MS) {
          results.offset = i;
          break;
        }

        const app = apps[i];
        results.appsChecked++;

        if (!app.package_name) continue;

        if (app.icon_key) {
          try {
            const res = await fetch(publicImageUrl(env, app.icon_key));
            if (!res.ok) {
              results.icons.skipped++;
              console.log(JSON.stringify({ tag: "normalise_skip", appId: app.id, slot: "icon", status: res.status }));
            } else {
              const normed = await normaliseIcon(new Uint8Array(await res.arrayBuffer()));
              await putImageObject(env, app.package_name, "icon", normed, "image/png");
              results.icons.processed++;
              console.log(JSON.stringify({ tag: "normalise_ok", appId: app.id, packageName: app.package_name, slot: "icon" }));
            }
          } catch (e) {
            results.icons.failed++;
            const msg = String(e?.message || e);
            results.errors.push({ appId: app.id, packageName: app.package_name, slot: "icon", error: msg });
            console.log(JSON.stringify({ tag: "normalise_fail", appId: app.id, packageName: app.package_name, slot: "icon", error: msg }));
          }
        } else {
          results.icons.skipped++;
        }

        const screenshotKeys = parseScreenshots(app.screenshots_json);
        for (let s = 0; s < screenshotKeys.length; s++) {
          if (Date.now() - startedAt >= DEADLINE_MS) {
            results.offset = i;
            break;
          }
          const slot = `screenshot_${s + 1}`;
          try {
            const res = await fetch(publicImageUrl(env, screenshotKeys[s]));
            if (!res.ok) {
              results.screenshots.skipped++;
              console.log(JSON.stringify({ tag: "normalise_skip", appId: app.id, slot, status: res.status }));
              continue;
            }
            const normed = await normaliseScreenshot(new Uint8Array(await res.arrayBuffer()));
            await putImageObject(env, app.package_name, slot, normed, "image/png");
            results.screenshots.processed++;
            console.log(JSON.stringify({ tag: "normalise_ok", appId: app.id, packageName: app.package_name, slot }));
          } catch (e) {
            results.screenshots.failed++;
            const msg = String(e?.message || e);
            results.errors.push({ appId: app.id, packageName: app.package_name, slot, error: msg });
            console.log(JSON.stringify({ tag: "normalise_fail", appId: app.id, packageName: app.package_name, slot, error: msg }));
          }
        }

        if (results.offset !== null) break;
      }

      results.totalIcons.processed       += results.icons.processed;
      results.totalIcons.skipped         += results.icons.skipped;
      results.totalIcons.failed          += results.icons.failed;
      results.totalScreenshots.processed += results.screenshots.processed;
      results.totalScreenshots.skipped   += results.screenshots.skipped;
      results.totalScreenshots.failed    += results.screenshots.failed;

      console.log(JSON.stringify({ tag: "normalise_batch", offset, nextOffset: results.offset, elapsed: Date.now() - startedAt }));

      return json({ ok: true, ...results });
    }

    const ratingsResponse = await handleRatingsRoute(request, env, path, method);
    if (ratingsResponse) return ratingsResponse;

    if (
      (method === "GET"    && path === "/admin/store/ratings") ||
      (method === "DELETE" && path.startsWith("/admin/store/ratings/"))
    ) {
      const me2 = await requireUser();
      const adminRatingsResponse = await handleAdminRatingsRoute(request, env, path, method, me2);
      if (adminRatingsResponse) return adminRatingsResponse;
    }

    return notFound();

  } catch (e) {
    console.log(JSON.stringify({
      tag:   "store_error",
      error: String(e?.message || e),
      stack: String(e?.stack   || ""),
    }));
    return json({ error: "internal_error", detail: String(e?.message || e) }, 500);
  }
}