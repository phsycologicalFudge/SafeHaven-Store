import { getStoreAppById, setAppSigningKeyHash, setAppImages, getSubmissionById, markSubmissionScanning, recordScanResult, rejectSubmission, REJECTION_REASONS, SUBMISSION_STATUS, APP_STATUS, setAppSigningFlag, getLiveSubmissionForRescan, recordRescanResult, getSubmissionByVersionCode, deleteSubmissionById } from "../db/index.js";
import { getIndex, applyAppEntryAndVersion, putImageObject, deleteStagingApk, putIndexWithChangelog } from "../storage/index.js";
import { normaliseIcon } from "../../modules/images/icon_normalise.js";
import { nowUnix, parseScreenshots, buildIndexAppEntry } from "../../helpers/store_helpers.js";
import { json, readJson, unauthorized, badRequest, notFound, isScannerAuth } from "../http/responses.js";
import { buildVersionEntry, approveAndPublish } from "../services/publish.js";
import { getVersionConflictState, clearReplaceableSubmissions } from "../services/version_conflict.js";

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

export const routes = [
  {
    methods: ["POST"],
    match: (path) => path === "/internal/store/rescan-result",
    handle: async ({ request, env }) => {
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
          await applyAppEntryAndVersion(
            env,
            buildIndexAppEntry(env, updatedApp),
            buildVersionEntry({
              ...submission,
              package_name: updatedApp.package_name,
              version_code: finalVersionCode,
              version_name: finalVersionName,
              apk_sha256: update?.apkSha256,
              apk_size: update?.apkSize,
              scanned_at: update?.scannedAt,
            }),
            versionChanged ? { removeVersionCode: submission.version_code } : {}
          );
        }
      }

      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/internal/store/scan-result",
    handle: async ({ request, env }) => {
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
          await rejectSubmission(env, submissionId, REJECTION_REASONS.DUPLICATE_APK_SHA256, null);
          return json({ ok: true, deduplicated: true });
        }
      }

      if (Number.isFinite(realVersionCode) && realVersionCode > 0) {
        if (realVersionCode !== Number(submission.version_code)) {
          const versionState = await getVersionConflictState(
            env,
            submission.app_id,
            realVersionCode,
            submissionId
          );

          if (versionState.type === "live") {
            await rejectSubmission(
              env,
              submissionId,
              REJECTION_REASONS.DUPLICATE_VERSION_CODE,
              null
            );

            return json({
              ok: true,
              deduplicated: true,
              existingStatus: SUBMISSION_STATUS.LIVE,
            });
          }

          if (versionState.type === "in_flight") {
            await deleteStagingApk(
              env,
              submission.package_name,
              submission.version_code
            ).catch(() => {});

            await deleteSubmissionById(env, submissionId);

            return json({
              ok: true,
              deduplicated: true,
              existingStatus: versionState.submission.status,
            });
          }

          if (versionState.type === "cooldown") {
            await rejectSubmission(
              env,
              submissionId,
              REJECTION_REASONS.RETRY_COOLDOWN,
              null
            );

            return json({
              ok: true,
              retryBlocked: true,
              retryAfter: versionState.retryAfter,
            });
          }

          await clearReplaceableSubmissions(
            env,
            versionState.replaceable
          );
        }

        await env.api_control_db
          .prepare(
            `UPDATE store_submissions
             SET version_code = ?1,
                 version_name = COALESCE(?2, version_name)
             WHERE id = ?3`
          )
          .bind(
            realVersionCode,
            realVersionName,
            submissionId
          )
          .run();

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
              await rejectSubmission(
                env,
                submissionId,
                REJECTION_REASONS.PACKAGE_NAME_MISMATCH,
                null
              );

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


      if (body.passed) {
        const selfApp = await getStoreAppById(env, submission.app_id);
        if (selfApp?.package_name === "com.colourswift.safehaven") {
          const freshSubmission = await getSubmissionById(env, submissionId);
          if (freshSubmission?.status === SUBMISSION_STATUS.PENDING_REVIEW) {
            try {
              await approveAndPublish(env, freshSubmission, null);
            } catch (e) {
              console.log(JSON.stringify({ tag: "safehaven_self_approve_failed", error: String(e?.message || e) }));
            }
          }
        }
      }

      return json({ ok: true });
    },
  },
];
