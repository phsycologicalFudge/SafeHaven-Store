const nowUnix = () => Math.floor(Date.now() / 1000);

const cryptoRandomHex = (bytes) => {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
};

const db = (env) => env.api_control_db;

export const SUBMISSION_STATUS = {
  PENDING_UPLOAD:  "pending_upload",
  PENDING_SCAN:    "pending_scan",
  SCANNING:        "scanning",
  PENDING_REVIEW:  "pending_review",
  LIVE:            "live",
  REJECTED:        "rejected",
};

export const APP_STATUS = {
  ACTIVE:    "active",
  SUSPENDED: "suspended",
  REMOVED:   "removed",
};

export const TRUST_LEVEL = {
  VERIFIED_SOURCE:    "verified_source",
  SECURITY_REVIEWED:  "security_reviewed",
};

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
  if (!Object.values(TRUST_LEVEL).includes(trustLevel)) return;
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
    .prepare("UPDATE store_apps SET icon_key = ?2, screenshots_json = ?3, updated_at = ?4 WHERE id = ?1")
    .bind((appId || "").toString().trim(), icon, screenshots, nowUnix())
    .run();
}

export async function createSubmission(env, input) {
  const id          = cryptoRandomHex(16);
  const appId       = (input.appId || "").toString().trim();
  const developerId = (input.developerId || "").toString().trim();
  const packageName = (input.packageName || "").toString().trim();
  const versionName = (input.versionName || "").toString().trim();
  const versionCode = Number(input.versionCode);
  const stagingKey  = (input.stagingKey || "").toString().trim();
  const now         = nowUnix();

  if (!appId || !developerId || !packageName || !versionName || !Number.isFinite(versionCode)) return null;

  await db(env)
    .prepare(
      "INSERT INTO store_submissions (id, app_id, developer_id, package_name, version_name, version_code, status, staging_key, submitted_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)"
    )
    .bind(id, appId, developerId, packageName, versionName, versionCode, SUBMISSION_STATUS.PENDING_UPLOAD, stagingKey, now)
    .run();

  return id;
}

export async function getSubmissionById(env, id) {
  const clean = (id || "").toString().trim();
  if (!clean) return null;
  return db(env)
    .prepare("SELECT * FROM store_submissions WHERE id = ?1 LIMIT 1")
    .bind(clean)
    .first();
}

export async function getSubmissionsByApp(env, appId) {
  const clean = (appId || "").toString().trim();
  if (!clean) return [];
  const rows = await db(env)
    .prepare("SELECT * FROM store_submissions WHERE app_id = ?1 ORDER BY version_code DESC")
    .bind(clean)
    .all();
  return rows.results || [];
}

export async function getSubmissionsByDeveloper(env, developerId) {
  const clean = (developerId || "").toString().trim();
  if (!clean) return [];
  const rows = await db(env)
    .prepare("SELECT * FROM store_submissions WHERE developer_id = ?1 ORDER BY submitted_at DESC")
    .bind(clean)
    .all();
  return rows.results || [];
}

export async function getSubmissionsByStatus(env, status) {
  const rows = await db(env)
    .prepare("SELECT * FROM store_submissions WHERE status = ?1 ORDER BY submitted_at ASC")
    .bind(status)
    .all();
  return rows.results || [];
}

export async function advanceSubmissionToScan(env, id) {
  await db(env)
    .prepare("UPDATE store_submissions SET status = ?2, updated_at = ?3 WHERE id = ?1 AND status = ?4")
    .bind((id || "").toString().trim(), SUBMISSION_STATUS.PENDING_SCAN, nowUnix(), SUBMISSION_STATUS.PENDING_UPLOAD)
    .run();
}

export async function cancelSubmission(env, id) {
  const clean = (id || "").toString().trim();
  if (!clean) return;
  await db(env)
    .prepare("UPDATE store_submissions SET status = ?2, rejection_reason = ?3, updated_at = ?4 WHERE id = ?1 AND status = ?5")
    .bind(clean, SUBMISSION_STATUS.REJECTED, "developer_cancelled", nowUnix(), SUBMISSION_STATUS.PENDING_UPLOAD)
    .run();
}

export async function markSubmissionScanning(env, id) {
  await db(env)
    .prepare("UPDATE store_submissions SET status = ?2, updated_at = ?3 WHERE id = ?1 AND status = ?4")
    .bind((id || "").toString().trim(), SUBMISSION_STATUS.SCANNING, nowUnix(), SUBMISSION_STATUS.PENDING_SCAN)
    .run();
}

export async function recordScanResult(env, id, input) {
  const clean       = (id || "").toString().trim();
  const passed      = input.passed ? 1 : 0;
  const scanResult  = typeof input.detail === "object" ? JSON.stringify(input.detail) : (input.detail || null);
  const apkSha256   = (input.apkSha256 || "").toString().trim() || null;
  const apkSize     = Number.isFinite(Number(input.apkSize)) ? Number(input.apkSize) : null;
  const now         = nowUnix();
  const reviewAfter = passed ? now + 21600 : null;
  const nextStatus  = passed ? SUBMISSION_STATUS.PENDING_REVIEW : SUBMISSION_STATUS.REJECTED;

  await db(env)
    .prepare(
      "UPDATE store_submissions SET status = ?2, scan_passed = ?3, scan_result = ?4, apk_sha256 = ?5, apk_size = ?6, scanned_at = ?7, review_after = ?8, updated_at = ?7 WHERE id = ?1"
    )
    .bind(clean, nextStatus, passed, scanResult, apkSha256, apkSize, now, reviewAfter)
    .run();
}

export async function approveSubmission(env, id, apkKey, reviewedBy = null) {
  const clean = (id || "").toString().trim();
  const now   = nowUnix();
  await db(env)
    .prepare(
      "UPDATE store_submissions SET status = ?2, apk_key = ?3, reviewed_by = ?4, updated_at = ?5 WHERE id = ?1 AND status IN ('pending_review')"
    )
    .bind(clean, SUBMISSION_STATUS.LIVE, apkKey, reviewedBy, now)
    .run();
}

export async function rejectSubmission(env, id, reason, reviewedBy = null) {
  const clean = (id || "").toString().trim();
  await db(env)
    .prepare(
      "UPDATE store_submissions SET status = ?2, rejection_reason = ?3, reviewed_by = ?4, updated_at = ?5 WHERE id = ?1"
    )
    .bind(clean, SUBMISSION_STATUS.REJECTED, (reason || "").toString().trim() || null, reviewedBy, nowUnix())
    .run();
}

export async function getSubmissionsDueForAutoApproval(env) {
  const now  = nowUnix();
  const rows = await db(env)
    .prepare(
      "SELECT * FROM store_submissions WHERE status = ?1 AND review_after IS NOT NULL AND review_after <= ?2 ORDER BY review_after ASC"
    )
    .bind(SUBMISSION_STATUS.PENDING_REVIEW, now)
    .all();
  return rows.results || [];
}

export async function getAllLiveApps(env) {
  const rows = await db(env)
    .prepare(
      `SELECT sa.*, ss.id AS submission_id, ss.version_name, ss.version_code, ss.apk_key, ss.apk_size, ss.apk_sha256, ss.scanned_at
       FROM store_apps sa
       JOIN store_submissions ss ON ss.id = (
         SELECT id FROM store_submissions
         WHERE app_id = sa.id AND status = 'live'
         ORDER BY version_code DESC
         LIMIT 1
       )
       WHERE sa.status = 'active'
       ORDER BY sa.package_name ASC`
    )
    .all();
  return rows.results || [];
}