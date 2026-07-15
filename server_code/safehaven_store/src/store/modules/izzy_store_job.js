import {
  createSubmission,
  advanceSubmissionToScan,
  setAppImages,
  getStoreAppByPackage,
  getStoreAppById,
  APP_STATUS,
} from "../store_db.js";

import {
  getPresignedStagingUploadUrl,
  addOrUpdateApp,
} from "../storage.js";
import { uploadImageFromUrl } from "./images/image_upload.js";

import { nowUnix, cryptoRandomHex, normalizeStoreText, parseScreenshots, buildIndexAppEntry, COMMUNITY_DEVELOPER_ID, fetchWithTimeout } from "../helpers/store_helpers.js";
import { releaseNotesFromFdroid } from "../helpers/changelog_helpers.js";

const createUnclaimedStoreApp = async (env, input) => {
  const packageName = (input.packageName || "").toString().trim();
  const name        = (input.name        || "").toString().trim();
  const repoUrl     = (input.repoUrl     || "").toString().trim();
  const summary     = normalizeStoreText(input.summary);
  const description = normalizeStoreText(input.description);
  const now         = nowUnix();
  if (!packageName || !name) return null;

  const existing = await env.api_control_db
    .prepare("SELECT id, status, trust_level, upstream FROM store_apps WHERE package_name = ?1 LIMIT 1")
    .bind(packageName)
    .first();

  if (existing) {
    if (existing.status !== APP_STATUS.ACTIVE || existing.trust_level !== "verified_source" || existing.upstream !== "izzy") {
      await env.api_control_db
        .prepare(
          "UPDATE store_apps SET name = ?2, summary = ?3, description = ?4, repo_url = ?5, status = 'active', trust_level = 'verified_source', repo_verified = 1, auto_tracked = 1, upstream = 'izzy', updated_at = ?6 WHERE id = ?1"
        )
        .bind(existing.id, name, summary, description, repoUrl, now)
        .run();
    }
    return existing.id;
  }

  const id = cryptoRandomHex(16);
  await env.api_control_db
    .prepare(
      `INSERT INTO store_apps
        (id, developer_id, package_name, name, summary, description,
         repo_url, repo_token, repo_verified, trust_level, status,
         claimed, auto_tracked, created_at, updated_at, upstream)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, '', 1, 'verified_source', 'active', 0, 1, ?8, ?8, 'izzy')`
    )
    .bind(id, COMMUNITY_DEVELOPER_ID, packageName, name, summary, description, repoUrl, now)
    .run();
  return id;
};

const IZZY_REPO_URL = "https://apt.izzysoft.de/fdroid/repo";
const IZZY_INDEX_URL = `${IZZY_REPO_URL}/index-v1.json`;
const IZZY_SYNC_LIMIT = 25;
const MAX_APK_BYTES = 100 * 1024 * 1024;
const MAX_ICON_BYTES = 4 * 1024 * 1024;
const MAX_SCREENSHOT_BYTES = 4 * 1024 * 1024;

const resolveIzzyRepoUrl = (appMeta) => {
  const sourceCode = (appMeta?.sourceCode || "").toString().trim();
  if (sourceCode) return sourceCode;
  const webSite = (appMeta?.webSite || "").toString().trim();
  return webSite || null;
};

const uploadIzzyImage = (env, packageName, slot, imageUrl, maxBytes) =>
  uploadImageFromUrl(env, packageName, slot, imageUrl, maxBytes);

const syncIzzyIcon = async (env, app, appMeta, packageName) => {
  if (!app) return null;
  if (app.icon_key) return app.icon_key;

  const localized = appMeta?.localized?.["en-US"] || {};
  let key = null;

  if (localized.icon) {
    key = await uploadIzzyImage(
      env, packageName, "icon",
      `${IZZY_REPO_URL}/${packageName}/en-US/${localized.icon}`,
      MAX_ICON_BYTES
    );
  }

  if (!key && appMeta?.icon) {
    key = await uploadIzzyImage(
      env, packageName, "icon",
      `${IZZY_REPO_URL}/icons/${appMeta.icon}`,
      MAX_ICON_BYTES
    );
  }

  if (!key && appMeta?.icon) {
    const sizes = [640, 160];
    for (let i = 0; i < sizes.length; i++) {
      key = await uploadIzzyImage(
        env, packageName, "icon",
        `${IZZY_REPO_URL}/icons-${sizes[i]}/${appMeta.icon}`,
        MAX_ICON_BYTES
      );
      if (key) break;
    }
  }

  if (!key && appMeta?.icon) {
    key = await uploadIzzyImage(
      env, packageName, "icon",
      `${IZZY_REPO_URL}/${appMeta.icon}`,
      MAX_ICON_BYTES
    );
  }

  return key;
};

const syncIzzyScreenshots = async (env, app, appMeta, packageName) => {
  if (!app) return [];

  const existingScreenshots = parseScreenshots(app.screenshots_json);
  if (existingScreenshots.length > 0) return existingScreenshots;

  const localized = appMeta?.localized?.["en-US"] || {};
  const screenshotFiles =
    appMeta?.phoneScreenshots ||
    localized.phoneScreenshots || [];

  if (!Array.isArray(screenshotFiles) || !screenshotFiles.length) return [];

  const screenshotKeys = [];
  let basePath = `${IZZY_REPO_URL}/${packageName}/en-US/phoneScreenshots`;
  let pathResolved = false;

  for (let i = 0; i < screenshotFiles.length && screenshotKeys.length < 6; i++) {
    const filename = screenshotFiles[i];
    const slot = `screenshot_${screenshotKeys.length + 1}`;

    let key = await uploadIzzyImage(env, packageName, slot, `${basePath}/${filename}`, MAX_SCREENSHOT_BYTES);

    if (!key && !pathResolved) {
      basePath = `${IZZY_REPO_URL}/${packageName}/phoneScreenshots`;
      key = await uploadIzzyImage(env, packageName, slot, `${basePath}/${filename}`, MAX_SCREENSHOT_BYTES);
    }

    pathResolved = true;
    if (key) screenshotKeys.push(key);
  }

  if (screenshotKeys.length > 0) {
    await setAppImages(env, app.id, {
      iconKey: app.icon_key || null,
      screenshotKeys,
    });
  }

  return screenshotKeys;
};

export const importOrUpdateIzzyApp = async (env, izzyApp) => {
  const packageName = izzyApp.packageName;
  if (!packageName) return { skipped: true, reason: "missing_package_name" };

  const localized = izzyApp.localized?.["en-US"] || {};
  const resolvedName = (izzyApp.name || localized.name || packageName).toString().trim();
  const resolvedSummary = normalizeStoreText(izzyApp.summary || localized.summary);
  const resolvedDescription = normalizeStoreText(izzyApp.description || localized.description);
  const resolvedVersionName = izzyApp.versionName ?? null;
  const resolvedWhatsNew = releaseNotesFromFdroid(localized);

  let app = await getStoreAppByPackage(env, packageName);

  if (app && app.upstream !== "izzy") {
    return { skipped: true, reason: "app_already_exists" };
  }

  const isNew = !app;
  const latestVersionCode = izzyApp.versionCode;

  if (!Number.isInteger(latestVersionCode) || latestVersionCode <= 0) {
    return { skipped: true, reason: "invalid_version_code" };
  }

  if (!isNew && Number(app.claimed) === 1) {
    return { skipped: true, reason: "app_claimed" };
  }

  if (!isNew) {
    const latestSubmission = await env.api_control_db
      .prepare(
        "SELECT version_code FROM store_submissions WHERE app_id = ?1 ORDER BY version_code DESC LIMIT 1"
      )
      .bind(app.id)
      .first();
    if (latestSubmission && Number(latestSubmission.version_code) >= latestVersionCode) {
      if (!app.icon_key) {
        const newIconKey = await syncIzzyIcon(env, app, izzyApp, packageName);
        if (newIconKey) {
          let screenshotKeys = [];
          try { screenshotKeys = JSON.parse(app.screenshots_json || "[]"); } catch { }
          if (screenshotKeys.length === 0) {
            screenshotKeys = await syncIzzyScreenshots(env, app, izzyApp, packageName);
          }
          await setAppImages(env, app.id, {
            iconKey: newIconKey,
            screenshotKeys: screenshotKeys,
          });
          const updatedApp = await getStoreAppById(env, app.id);
          if (updatedApp) {
            await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
          }
        }
      }

      return {
        skipped: true,
        reason: "version_not_newer",
        packageName,
        currentVersion: latestSubmission.version_code,
        izzyVersion: latestVersionCode,
      };
    }
  }

  let repoUrl = resolveIzzyRepoUrl(izzyApp);
  if (!repoUrl && app?.repo_url) repoUrl = app.repo_url;

  if (isNew) {
    const id = await createUnclaimedStoreApp(env, {
      packageName,
      name: resolvedName,
      summary: resolvedSummary,
      description: resolvedDescription,
      repoUrl,
      iconKey: null,
      category: "other",
    });
    if (!id) return { skipped: true, reason: "app_create_failed" };
    app = await getStoreAppById(env, id);
  } else {
    const updates = {};
    if (app.name !== resolvedName) updates.name = resolvedName;
    if (app.summary !== resolvedSummary) updates.summary = resolvedSummary;
    if (app.description !== resolvedDescription) updates.description = resolvedDescription;
    if (app.repo_url !== repoUrl) updates.repo_url = repoUrl;

    if (Object.keys(updates).length > 0) {
      await env.api_control_db
        .prepare(
          `UPDATE store_apps SET name = COALESCE(?2, name), summary = COALESCE(?3, summary), description = COALESCE(?4, description), repo_url = COALESCE(?5, repo_url), updated_at = ?6 WHERE id = ?1`
        )
        .bind(
          app.id,
          updates.name ?? null,
          updates.summary ?? null,
          updates.description ?? null,
          updates.repo_url ?? null,
          nowUnix()
        )
        .run();
      app = { ...app, ...updates };
    }
  }

  if (izzyApp.size && izzyApp.size > MAX_APK_BYTES) {
    return {
      skipped: true,
      reason: "apk_too_large",
      size: izzyApp.size,
      packageName,
      versionCode: latestVersionCode,
    };
  }

  const existingSubmission = await env.api_control_db
    .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND version_code = ?2 LIMIT 1")
    .bind(app.id, latestVersionCode)
    .first();

  if (existingSubmission) {
    return { skipped: true, reason: "submission_already_exists", packageName, versionCode: latestVersionCode };
  }

  let iconKey = await syncIzzyIcon(env, app, izzyApp, packageName);
  let screenshotKeys = [];
  if (latestVersionCode && Number.isInteger(latestVersionCode) && latestVersionCode > 0) {
    screenshotKeys = await syncIzzyScreenshots(env, app, izzyApp, packageName);
  }

  const hasIcon = !!iconKey;
  const hasScreenshots = screenshotKeys.length > 0;
  const apkName = izzyApp.apkName || `${packageName}_${latestVersionCode}.apk`;
  const apkUrl = `${IZZY_REPO_URL}/${apkName}`;

  let apkBuffer;
  try {
    const res = await fetchWithTimeout(apkUrl, { headers: { "user-agent": "SafeHaven-Store/1.0" } }, 20000);
    if (!res.ok) return { skipped: true, reason: `apk_download_failed:${res.status}`, packageName, versionCode: latestVersionCode };
    apkBuffer = await res.arrayBuffer();
  } catch (e) {
    return { skipped: true, reason: `apk_download_error:${String(e?.message || e)}`, packageName, versionCode: latestVersionCode };
  }

  if (apkBuffer.byteLength > MAX_APK_BYTES) {
    return {
      skipped: true,
      reason: "apk_too_large_post_download",
      size: apkBuffer.byteLength,
      packageName,
      versionCode: latestVersionCode,
    };
  }

  try {
    const stagingUrl = await getPresignedStagingUploadUrl(env, packageName, latestVersionCode, 300);
    const uploadRes = await fetchWithTimeout(stagingUrl, {
      method: "PUT",
      headers: { "content-type": "application/vnd.android.package-archive" },
      body: apkBuffer,
    }, 20000);
    if (!uploadRes.ok) throw new Error(`staging_upload_failed:${uploadRes.status}`);
  } catch (e) {
    return { skipped: true, reason: `staging_failed:${String(e?.message || e)}`, packageName, versionCode: latestVersionCode };
  }

  const submissionId = await createSubmission(env, {
    appId: app.id,
    developerId: COMMUNITY_DEVELOPER_ID,
    packageName,
    versionName: resolvedVersionName,
    versionCode: latestVersionCode,
    stagingKey: `staging/${packageName}/${latestVersionCode}/app.apk`,
    releaseNotes: resolvedWhatsNew,
  });

  if (!submissionId) return { skipped: true, reason: "submission_create_failed", packageName, versionCode: latestVersionCode };

  await advanceSubmissionToScan(env, submissionId);

  const updatedApp = await getStoreAppById(env, app.id);
  if (updatedApp) {
    await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
  }

  return {
    imported: true,
    packageName,
    versionCode: latestVersionCode,
    submissionId,
    hasIcon,
    hasScreenshots,
    isNew,
  };
};

const IZZY_OFFSET_KEY = "izzy_sync_offset";

const getSyncState = async (env, key) => {
  try {
    const row = await env.api_control_db
      .prepare("SELECT value FROM sync_state WHERE key = ?1 LIMIT 1")
      .bind(key)
      .first();
    return row ? JSON.parse(row.value) : null;
  } catch {
    return null;
  }
};

const setSyncState = async (env, key, value) => {
  await env.api_control_db
    .prepare("INSERT OR REPLACE INTO sync_state (key, value) VALUES (?1, ?2)")
    .bind(key, JSON.stringify(value))
    .run();
};

const IZZY_UPDATE_CURSOR_KEY = "izzy_update_cursor";

export async function runIzzyUpdateCheck(env, options = {}) {
  const timeBudgetMs = options.timeBudgetMs ?? 300_000;
  const deadline = Date.now() + timeBudgetMs;

  const results = {
    checked: 0,
    updated: 0,
    skipped: 0,
    skipReasons: {},
    errors: [],
    wrapped: false,
  };

  let index;
  try {
    const obj = await env.SH_BUCKET.get("izzy/index-v1.json");
    if (!obj) return { error: "izzy_index_not_cached" };
    index = await obj.json();
  } catch (e) {
    return { error: String(e?.message || e) };
  }

  const appsMap = Object.fromEntries(
    (index.apps || []).map((a) => [a.packageName, a])
  );

  const latestByPackage = new Map();
  for (const [packageName, versions] of Object.entries(index.packages || {})) {
    if (!Array.isArray(versions) || !versions.length) continue;
    const latest = versions.reduce((a, b) => b.versionCode > a.versionCode ? b : a);
    latestByPackage.set(packageName, latest);
  }

  const PAGE_SIZE = 500;
  let lastId = options.cursor ?? (await getSyncState(env, IZZY_UPDATE_CURSOR_KEY)) ?? "";

  while (Date.now() < deadline) {
    const rows = await env.api_control_db
      .prepare(
        `SELECT id, package_name
         FROM store_apps
         WHERE upstream = 'izzy'
           AND status = 'active'
           AND claimed = 0
           AND id > ?1
         ORDER BY id ASC
         LIMIT ?2`
      )
      .bind(lastId, PAGE_SIZE)
      .all();

    const apps = rows.results || [];
    if (!apps.length) {
      lastId = "";
      results.wrapped = true;
      break;
    }

    for (const app of apps) {
      results.checked++;

      const latest = latestByPackage.get(app.package_name);
      if (!latest) {
        results.skipped++;
        results.skipReasons["not_in_izzy_index"] = (results.skipReasons["not_in_izzy_index"] || 0) + 1;
        continue;
      }

      const appMeta = appsMap[app.package_name] || {};
      const izzyApp = { packageName: app.package_name, ...appMeta, ...latest };

      try {
        const outcome = await importOrUpdateIzzyApp(env, izzyApp);
        if (outcome.imported) {
          results.updated++;
        } else {
          results.skipped++;
          const reason = outcome.reason || "unknown";
          results.skipReasons[reason] = (results.skipReasons[reason] || 0) + 1;
        }
      } catch (e) {
        results.errors.push({ packageName: app.package_name, error: String(e?.message || e) });
      }

      if (Date.now() >= deadline) break;
    }

    lastId = apps[apps.length - 1].id;
    if (apps.length < PAGE_SIZE) {
      lastId = "";
      results.wrapped = true;
      break;
    }
  }

  await setSyncState(env, IZZY_UPDATE_CURSOR_KEY, lastId);

  console.log(JSON.stringify({
    tag: "izzy_update_check_complete",
    checked: results.checked,
    updated: results.updated,
    skipped: results.skipped,
    skipReasons: results.skipReasons,
    errorCount: results.errors.length,
    errors: results.errors.slice(0, 20),
    wrapped: results.wrapped,
    cursor: lastId,
  }));

  return results;
}

export async function runIzzySync(env, options = {}) {
  const batchSize    = options.batchSize   || IZZY_SYNC_LIMIT;
  const timeBudgetMs = options.timeBudgetMs ?? 300_000;
  const forceOffset  = options.offset ?? null;

  const results = {
    processed: 0,
    imported: 0,
    updated: 0,
    skipped: 0,
    skipReasons: {},
    importedPackages: [],
    updatedPackages: [],
    errors: [],
    offsetStart: 0,
    offsetEnd: 0,
    totalPackages: 0,
    wrapped: false,
  };

  let index;
  try {
    const obj = await env.SH_BUCKET.get("izzy/index-v1.json");
    if (!obj) return { error: "izzy_index_not_cached" };
    index = await obj.json();
  } catch (e) {
    console.error(JSON.stringify({ tag: "izzy_index_error", error: String(e?.message || e) }));
    return { error: String(e?.message || e) };
  }

  const appsMap = Object.fromEntries(
    (index.apps || []).map((a) => [a.packageName, a])
  );

  const packagesMap = index.packages || {};
  const packageEntries = Object.entries(packagesMap);
  const total = packageEntries.length;
  results.totalPackages = total;

  if (total === 0) {
    console.log(JSON.stringify({ tag: "izzy_sync_complete", ...results }));
    return results;
  }

  let offset = forceOffset !== null
    ? Number(forceOffset)
    : ((await getSyncState(env, IZZY_OFFSET_KEY)) ?? 0);

  if (!Number.isFinite(offset) || offset < 0 || offset >= total) offset = 0;
  results.offsetStart = offset;

  const deadline = Date.now() + timeBudgetMs;
  const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  const cutoffDateMs = Date.now() - ONE_YEAR_MS;

  while (Date.now() < deadline) {
    if (offset >= total) {
      offset = 0;
      results.wrapped = true;
      break;
    }

    const end = Math.min(offset + batchSize, total);
    const batch = packageEntries.slice(offset, end);

    for (const [packageName, versions] of batch) {
      if (!Array.isArray(versions) || !versions.length) {
        results.processed++;
        results.skipped++;
        results.skipReasons["no_versions"] = (results.skipReasons["no_versions"] || 0) + 1;
        continue;
      }

      const appMeta = appsMap[packageName] || {};
      const lastActivityMs = appMeta.lastUpdated || appMeta.added || 0;

      if (lastActivityMs > 0 && lastActivityMs < cutoffDateMs) {
        results.processed++;
        results.skipped++;
        results.skipReasons["abandoned_app"] = (results.skipReasons["abandoned_app"] || 0) + 1;
        continue;
      }

      const latestVersion = versions.reduce((latest, current) =>
        current.versionCode > latest.versionCode ? current : latest
      );

      const izzyApp = { packageName, ...appMeta, ...latestVersion };

      try {
        const outcome = await importOrUpdateIzzyApp(env, izzyApp);
        results.processed++;
        if (outcome.imported) {
          results.imported++;
          if (!outcome.isNew) {
            results.updated++;
            results.updatedPackages.push(packageName);
          } else {
            results.importedPackages.push(packageName);
          }
        } else if (outcome.skipped) {
          results.skipped++;
          const reason = outcome.reason || "unknown";
          results.skipReasons[reason] = (results.skipReasons[reason] || 0) + 1;
        }
      } catch (e) {
        results.errors.push({ packageName, error: String(e?.message || e) });
      }
    }

    offset = end >= total ? 0 : end;
    if (offset === 0) {
      results.wrapped = true;
      break;
    }

    if (Date.now() >= deadline) break;
  }

  results.offsetEnd = offset;
  await setSyncState(env, IZZY_OFFSET_KEY, offset);

  console.log(JSON.stringify({
    tag: "izzy_sync_complete",
    processed: results.processed,
    imported: results.imported,
    updated: results.updated,
    skipped: results.skipped,
    skipReasons: results.skipReasons,
    importedPackages: results.importedPackages,
    updatedPackages: results.updatedPackages,
    errorCount: results.errors.length,
    errors: results.errors.slice(0, 20),
    offsetStart: results.offsetStart,
    offsetEnd: results.offsetEnd,
    totalPackages: results.totalPackages,
    wrapped: results.wrapped,
  }));

  return results;
}

const IZZY_CRON_STATE_KEY = "izzy_cron_state";
const IZZY_LOCK_KEY = "izzy_cron_lock";
const UPDATE_CHECK_INTERVAL_SECONDS = 6 * 60 * 60;
const DISCOVERY_INTERVAL_SECONDS = 24 * 60 * 60;
const LOCK_TTL_SECONDS = 20 * 60;

const tryAcquireIzzyLock = async (env) => {
  const now = nowUnix();
  const expiresAt = now + LOCK_TTL_SECONDS;

  await env.api_control_db
    .prepare("INSERT OR IGNORE INTO sync_state (key, value) VALUES (?1, ?2)")
    .bind(IZZY_LOCK_KEY, JSON.stringify({ expiresAt: 0 }))
    .run();

  const result = await env.api_control_db
    .prepare(
      "UPDATE sync_state SET value = ?2 WHERE key = ?1 AND CAST(json_extract(value, '$.expiresAt') AS INTEGER) < ?3"
    )
    .bind(IZZY_LOCK_KEY, JSON.stringify({ expiresAt }), now)
    .run();

  return (result.meta?.changes || 0) > 0;
};

const releaseIzzyLock = async (env) => {
  await env.api_control_db
    .prepare("UPDATE sync_state SET value = ?2 WHERE key = ?1")
    .bind(IZZY_LOCK_KEY, JSON.stringify({ expiresAt: 0 }))
    .run();
};

export async function runIzzyCronJob(env) {
  const gotLock = await tryAcquireIzzyLock(env);
  if (!gotLock) {
    return { skipped: true, reason: "locked" };
  }

  try {
    let state = await getSyncState(env, IZZY_CRON_STATE_KEY) || {
      lastUpdateCheck: 0,
      lastDiscovery: 0,
      discoveryStatus: "idle",
    };

    const now = Math.floor(Date.now() / 1000);
    const output = { now };

    if (now - (state.lastUpdateCheck || 0) >= UPDATE_CHECK_INTERVAL_SECONDS) {
      output.updateCheck = await runIzzyUpdateCheck(env);
      state.lastUpdateCheck = now;
    }

    if (state.discoveryStatus === "syncing" || now - (state.lastDiscovery || 0) >= DISCOVERY_INTERVAL_SECONDS) {
      if (state.discoveryStatus !== "syncing") {
        await setSyncState(env, IZZY_OFFSET_KEY, 0);
        state.discoveryStatus = "syncing";
      }

      const discoveryResult = await runIzzySync(env);
      output.discovery = discoveryResult;

      if (discoveryResult.error || discoveryResult.wrapped) {
        state.discoveryStatus = "idle";
        state.lastDiscovery = now;
      }
    }

    await setSyncState(env, IZZY_CRON_STATE_KEY, state);
    return output;
  } finally {
    await releaseIzzyLock(env);
  }
}