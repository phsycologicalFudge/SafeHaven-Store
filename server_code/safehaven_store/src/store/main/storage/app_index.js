// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { CATEGORIES, INDEX_KEY, CHANGELOG_KEY, SEVEN_DAYS_SEC } from "./constants.js";
import { s3Fetch } from "./s3.js";

export const nowUnix = () => Math.floor(Date.now() / 1000);

export const emptyIndex = () => ({ version: 1, timestamp: nowUnix(), categories: CATEGORIES, apps: [] });

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

export const putIndexWithChangelog = async (env, newIndex, options = {}) => {
  const now = nowUnix();
  newIndex.timestamp = now;

  let updates;
  let removes;

  if (options.changedApps) {
    updates = options.changedApps;
    removes = options.removedPackageNames ?? [];
  } else {
    let oldIndex;
    try {
      oldIndex = await getIndex(env);
    } catch {
      oldIndex = emptyIndex();
    }

    const oldMap = new Map(oldIndex.apps.map((a) => [a.packageName, a]));
    const newSet = new Set(newIndex.apps.map((a) => a.packageName));

    updates = newIndex.apps.filter((newApp) => {
      const oldApp = oldMap.get(newApp.packageName);
      return !oldApp || JSON.stringify(oldApp) !== JSON.stringify(newApp);
    });

    removes = oldIndex.apps
      .filter((oa) => !newSet.has(oa.packageName))
      .map((oa) => oa.packageName);
  }

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

export const mergeAppEntry = (index, appEntry) => {
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
  return index.apps.find((a) => a.packageName === appEntry.packageName);
};

export const mergeVersionOnApp = (app, versionEntry) => {
  app.versions = app.versions ?? [];
  const vi = app.versions.findIndex((v) => v.versionCode === versionEntry.versionCode);
  if (vi === -1) {
    app.versions.push(versionEntry);
  } else {
    app.versions[vi] = versionEntry;
  }
  app.versions.sort((a, b) => b.versionCode - a.versionCode);
  app.lastUpdated = nowUnix();
};

export const addOrUpdateApp = async (env, appEntry) => {
  const index = await getIndex(env);
  const app   = mergeAppEntry(index, appEntry);
  await putIndexWithChangelog(env, index, { changedApps: [app] });
};

export const addVersionToApp = async (env, packageName, versionEntry) => {
  const index = await getIndex(env);
  const app   = index.apps.find((a) => a.packageName === packageName);
  if (!app) throw new Error("app_not_found");

  mergeVersionOnApp(app, versionEntry);
  await putIndexWithChangelog(env, index, { changedApps: [app] });
};

export const applyAppEntryAndVersion = async (env, appEntry, versionEntry, options = {}) => {
  const index = await getIndex(env);
  const app   = mergeAppEntry(index, appEntry);

  if (options.removeVersionCode != null) {
    app.versions = (app.versions ?? []).filter((v) => v.versionCode !== options.removeVersionCode);
  }

  mergeVersionOnApp(app, versionEntry);
  await putIndexWithChangelog(env, index, { changedApps: [app] });
  return app;
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
