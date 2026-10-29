import { getSubmissionsByVersionCode, isRetryBlockingRejection, getRetryAfterSeconds, SUBMISSION_STATUS, deleteSubmissionById } from "../db/index.js";
import { deleteStagingApk } from "../storage/index.js";

export const getVersionConflictState = async (
  env,
  appId,
  versionCode,
  excludeSubmissionId = null
) => {
  const rows = await getSubmissionsByVersionCode(
    env,
    appId,
    versionCode
  );

  const submissions = excludeSubmissionId
    ? rows.filter((row) => row.id !== excludeSubmissionId)
    : rows;

  const live = submissions.find(
    (row) => row.status === SUBMISSION_STATUS.LIVE
  );

  if (live) {
    return {
      type: "live",
      submission: live,
      retryAfter: null,
    };
  }

  const inFlight = submissions.find(
    (row) =>
      row.status === SUBMISSION_STATUS.PENDING_SCAN ||
      row.status === SUBMISSION_STATUS.SCANNING ||
      row.status === SUBMISSION_STATUS.PENDING_REVIEW
  );

  if (inFlight) {
    return {
      type: "in_flight",
      submission: inFlight,
      retryAfter: null,
    };
  }

  const coolingDown = submissions.find(
    (row) => isRetryBlockingRejection(row)
  );

  if (coolingDown) {
    return {
      type: "cooldown",
      submission: coolingDown,
      retryAfter: getRetryAfterSeconds(coolingDown),
    };
  }

  const replaceable = submissions.filter(
    (row) =>
      row.status === SUBMISSION_STATUS.PENDING_UPLOAD ||
      row.status === SUBMISSION_STATUS.REJECTED
  );

  return {
    type: "clear",
    replaceable,
    retryAfter: null,
  };
};

export const clearReplaceableSubmissions = async (
  env,
  submissions
) => {
  for (const submission of submissions || []) {
    await deleteStagingApk(
      env,
      submission.package_name,
      submission.version_code
    ).catch(() => {});

    await deleteSubmissionById(env, submission.id);
  }
};
