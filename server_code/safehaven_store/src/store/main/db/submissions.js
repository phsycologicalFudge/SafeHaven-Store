import { REJECTION_REASONS, SUBMISSION_STATUS, db, REJECTION_RETRY_COOLDOWN_SECONDS } from "./constants.js";
import { nowUnix, cryptoRandomHex } from "../../helpers/store_helpers.js";

export function isRetryBlockingRejection(submission, now = nowUnix()) {
  if (!submission || submission.status !== SUBMISSION_STATUS.REJECTED) {
    return false;
  }

  const reason = (submission.rejection_reason || "").toString().trim();

  const scannerRejected =
    reason === REJECTION_REASONS.SCAN_FAILED ||
    reason === REJECTION_REASONS.SIGNING_KEY_CHANGED ||
    reason === REJECTION_REASONS.PACKAGE_NAME_MISMATCH ||
    (
      !reason &&
      submission.scan_passed !== null &&
      submission.scan_passed !== undefined &&
      Number(submission.scan_passed) === 0
    );

  if (!scannerRejected) return false;

  const rejectedAt = Number(submission.updated_at || 0);
  if (!Number.isFinite(rejectedAt) || rejectedAt <= 0) return false;

  return rejectedAt + REJECTION_RETRY_COOLDOWN_SECONDS > now;
}

export function getRetryAfterSeconds(submission, now = nowUnix()) {
  const rejectedAt = Number(submission?.updated_at || 0);
  if (!Number.isFinite(rejectedAt) || rejectedAt <= 0) return 0;

  return Math.max(
    0,
    rejectedAt + REJECTION_RETRY_COOLDOWN_SECONDS - now
  );
}

export async function getSubmissionsByVersionCode(env, appId, versionCode) {
  const clean = (appId || "").toString().trim();
  const vc = Number(versionCode);

  if (!clean || !Number.isFinite(vc)) return [];

  const rows = await db(env)
    .prepare(
      `SELECT *
       FROM store_submissions
       WHERE app_id = ?1
         AND version_code = ?2
       ORDER BY submitted_at DESC`
    )
    .bind(clean, vc)
    .all();

  return rows.results || [];
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
    .prepare(
      "DELETE FROM store_submissions WHERE id = ?1 AND status = ?2"
    )
    .bind(clean, SUBMISSION_STATUS.PENDING_UPLOAD)
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
  const reviewAfter = passed ? now + 3600 : null;
  const nextStatus  = passed ? SUBMISSION_STATUS.PENDING_REVIEW : SUBMISSION_STATUS.REJECTED;
  const rejectionReason = passed ? null : REJECTION_REASONS.SCAN_FAILED;

  await db(env)
    .prepare(
      `UPDATE store_submissions
       SET status = ?2,
           scan_passed = ?3,
           scan_result = ?4,
           apk_sha256 = ?5,
           apk_size = ?6,
           scanned_at = ?7,
           review_after = ?8,
           rejection_reason = ?9,
           updated_at = ?7
       WHERE id = ?1`
    )
    .bind(
      clean,
      nextStatus,
      passed,
      scanResult,
      apkSha256,
      apkSize,
      now,
      reviewAfter,
      rejectionReason
    )
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

export const getLiveSubmissionForRescan = async (env, packageName, versionCode) => {
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

export const recordRescanResult = async (env, submissionId, input) => {
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

export const getSubmissionByVersionCode = async (env, appId, versionCode) =>
  env.api_control_db
    .prepare("SELECT * FROM store_submissions WHERE app_id = ?1 AND version_code = ?2 LIMIT 1")
    .bind((appId || "").toString().trim(), versionCode)
    .first();

export const deleteSubmissionById = async (env, submissionId) => {
  await env.api_control_db
    .prepare("DELETE FROM store_submissions WHERE id = ?1")
    .bind((submissionId || "").toString().trim())
    .run();
};
