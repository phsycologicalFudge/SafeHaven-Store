// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { getStoreAppById, approveSubmission, getSubmissionsDueForAutoApproval } from "../db/index.js";
import { applyAppEntryAndVersion, promoteStagingToProduction, apkKey } from "../storage/index.js";
import { normalizeStoreText, buildIndexAppEntry } from "../../helpers/store_helpers.js";

export const buildVersionEntry = (submission) => ({
  versionName: submission.version_name,
  versionCode: submission.version_code,
  apkPath:     submission.apk_key || apkKey(submission.package_name, submission.version_code),
  apkSize:     submission.apk_size   || null,
  sha256:      submission.apk_sha256 || null,
  scannedAt:   submission.scanned_at || null,
  added:       submission.submitted_at,
  whatsNew:    normalizeStoreText(submission.release_notes) || null,
});

export const approveAndPublish = async (env, submission, reviewedBy = null) => {
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
    await applyAppEntryAndVersion(
      env,
      buildIndexAppEntry(env, updatedApp),
      buildVersionEntry(updatedSubmission)
    );
  }
};

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
