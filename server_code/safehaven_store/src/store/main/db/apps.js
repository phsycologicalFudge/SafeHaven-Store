// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { APP_STATUS, TRUST_LEVEL, db } from "./constants.js";
import { nowUnix, cryptoRandomHex, normalizeStoreText, COMMUNITY_DEVELOPER_ID } from "../../helpers/store_helpers.js";

export async function getStoreAppByPackage(env, packageName) {
  const clean = (packageName || "").toString().trim();
  if (!clean) return null;
  return db(env)
    .prepare("SELECT * FROM store_apps WHERE package_name = ?1 LIMIT 1")
    .bind(clean)
    .first();
}

export async function getStoreAppById(env, id) {
  const clean = (id || "").toString().trim();
  if (!clean) return null;
  return db(env)
    .prepare("SELECT * FROM store_apps WHERE id = ?1 LIMIT 1")
    .bind(clean)
    .first();
}

export async function getStoreAppsByDeveloper(env, developerId) {
  const clean = (developerId || "").toString().trim();
  if (!clean) return [];
  const rows = await db(env)
    .prepare("SELECT * FROM store_apps WHERE developer_id = ?1 ORDER BY created_at DESC")
    .bind(clean)
    .all();
  return rows.results || [];
}

export async function getAllStoreApps(env) {
  const rows = await db(env)
    .prepare("SELECT * FROM store_apps WHERE status = ?1 ORDER BY created_at DESC")
    .bind(APP_STATUS.ACTIVE)
    .all();
  return rows.results || [];
}

export async function createStoreApp(env, input) {
  const id          = cryptoRandomHex(16);
  const packageName = (input.packageName || "").toString().trim();
  const developerId = (input.developerId || "").toString().trim();
  const name        = (input.name || "").toString().trim();
  const summary     = (input.summary || "").toString().trim() || null;
  const description = (input.description || "").toString().trim() || null;
  const repoUrl     = (input.repoUrl || "").toString().trim();
  const repoToken   = cryptoRandomHex(24);
  const now         = nowUnix();

  if (!packageName || !developerId || !name || !repoUrl) return null;

  await db(env)
    .prepare(
      "INSERT INTO store_apps (id, developer_id, package_name, name, summary, description, repo_url, repo_token, repo_verified, trust_level, status, created_at, updated_at, upstream) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10, ?11, ?11, NULL)"
    )
    .bind(
      id, developerId, packageName, name, summary, description,
      repoUrl, repoToken, TRUST_LEVEL.VERIFIED_SOURCE, APP_STATUS.ACTIVE, now
    )
    .run();

  return { id, repoToken };
}

export async function setAppRepoVerified(env, appId, verified) {
  await db(env)
    .prepare("UPDATE store_apps SET repo_verified = ?2, updated_at = ?3 WHERE id = ?1")
    .bind((appId || "").toString().trim(), verified ? 1 : 0, nowUnix())
    .run();
}

export async function setAppSigningKeyHash(env, appId, signingKeyHash) {
  await db(env)
    .prepare("UPDATE store_apps SET signing_key_hash = ?2, updated_at = ?3 WHERE id = ?1")
    .bind((appId || "").toString().trim(), (signingKeyHash || "").toString().trim(), nowUnix())
    .run();
}

export async function setAppTrustLevel(env, appId, trustLevel) {
  if (trustLevel !== null && !Object.values(TRUST_LEVEL).includes(trustLevel)) return;
  await db(env)
    .prepare("UPDATE store_apps SET trust_level = ?2, updated_at = ?3 WHERE id = ?1")
    .bind((appId || "").toString().trim(), trustLevel, nowUnix())
    .run();
}

export async function setAppStatus(env, appId, status) {
  if (!Object.values(APP_STATUS).includes(status)) return;
  await db(env)
    .prepare("UPDATE store_apps SET status = ?2, updated_at = ?3 WHERE id = ?1")
    .bind((appId || "").toString().trim(), status, nowUnix())
    .run();
}

export async function setAppCategory(env, appId, category) {
  const clean = (appId || "").toString().trim();
  if (!clean) return;
  await db(env)
    .prepare("UPDATE store_apps SET category = ?2, updated_at = ?3 WHERE id = ?1")
    .bind(clean, category || null, nowUnix())
    .run();
}

export async function setAppImages(env, appId, { iconKey, screenshotKeys }) {
  const icon        = (iconKey || "").toString().trim() || null;
  const screenshots = Array.isArray(screenshotKeys) && screenshotKeys.length
    ? JSON.stringify(screenshotKeys.filter(Boolean).map((k) => k.toString().trim()))
    : null;
  await db(env)
    .prepare("UPDATE store_apps SET icon_key = ?2, screenshots_json = ?3, image_version = image_version + 1, updated_at = ?4 WHERE id = ?1")
    .bind((appId || "").toString().trim(), icon, screenshots, nowUnix())
    .run();
}

export const setAppSigningFlag = async (env, appId, flag) => {
  await env.api_control_db
    .prepare("UPDATE store_apps SET signing_flag = ?2, updated_at = ?3 WHERE id = ?1")
    .bind((appId || "").toString().trim(), flag, nowUnix())
    .run();
};

export const createUnclaimedStoreApp = async (env, input) => {
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

export const setAppLastRepoCheck = async (env, appId) => {
  await env.api_control_db
    .prepare("UPDATE store_apps SET last_repo_check = ?2 WHERE id = ?1")
    .bind((appId || "").toString().trim(), nowUnix())
    .run();
};

export const setAppClaimed = async (env, appId, developerId) => {
  await env.api_control_db
    .prepare(
      "UPDATE store_apps SET claimed = 1, auto_tracked = 0, developer_id = ?2, trust_level = ?3, updated_at = ?4 WHERE id = ?1"
    )
    .bind((appId || "").toString().trim(), developerId, TRUST_LEVEL.VERIFIED_SOURCE, nowUnix())
    .run();
};
