export const db = (env) => env.api_control_db;

export const SUBMISSION_STATUS = {
  PENDING_UPLOAD:  "pending_upload",
  PENDING_SCAN:    "pending_scan",
  SCANNING:        "scanning",
  PENDING_REVIEW:  "pending_review",
  LIVE:            "live",
  REJECTED:        "rejected",
};

export const REJECTION_REASONS = {
  DEVELOPER_CANCELLED:     "developer_cancelled",
  UPLOAD_FAILED:           "upload_failed",
  SCAN_FAILED:             "scan_failed",
  SIGNING_KEY_CHANGED:     "signing_key_changed",
  PACKAGE_NAME_MISMATCH:   "package_name_mismatch",
  DUPLICATE_APK_SHA256:    "duplicate_apk_sha256",
  DUPLICATE_VERSION_CODE:  "duplicate_version_code",
  RETRY_COOLDOWN:          "retry_cooldown",
  ADMIN_REJECTED:          "admin_rejected",
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

export const REJECTION_RETRY_COOLDOWN_SECONDS = 24 * 60 * 60;
