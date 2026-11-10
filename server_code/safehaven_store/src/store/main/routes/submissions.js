// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { getStoreAppById, createSubmission, getSubmissionById, advanceSubmissionToScan, cancelSubmission, SUBMISSION_STATUS, APP_STATUS } from "../db/index.js";
import { getPresignedStagingUploadUrl, headStagingObject, deleteStagingApk, stagingKey } from "../storage/index.js";
import { normalizeStoreText } from "../../helpers/store_helpers.js";
import { json, readJson, unauthorized, forbidden, badRequest, notFound } from "../http/responses.js";
import { getVersionConflictState, clearReplaceableSubmissions } from "../services/version_conflict.js";

export const routes = [
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/submit$/),
    handle: async ({ request, env, path, requireUser }) => {
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
      const whatsNew     = normalizeStoreText(body.whatsNew) || null;

      if (!versionName)                                      return badRequest("missing_versionName");
      if (!Number.isFinite(versionCode) || versionCode < 1) return badRequest("invalid_versionCode");

      const versionState = await getVersionConflictState(
        env,
        appId,
        versionCode
      );

      if (versionState.type === "live") {
        return json({
          error: "version_code_already_live",
          submissionId: versionState.submission.id,
          status: versionState.submission.status,
        }, 409);
      }

      if (versionState.type === "in_flight") {
        return json({
          error: "version_already_processing",
          submissionId: versionState.submission.id,
          status: versionState.submission.status,
        }, 409);
      }

      if (versionState.type === "cooldown") {
        return json({
          error: "version_retry_cooldown",
          retryAfter: versionState.retryAfter,
        }, 429);
      }

      const pendingUpload = versionState.replaceable?.find(
        (row) => row.status === SUBMISSION_STATUS.PENDING_UPLOAD
      );

      if (pendingUpload) {
        const uploadUrl = await getPresignedStagingUploadUrl(
          env,
          app.package_name,
          versionCode
        );

        return json({
          ok: true,
          resumed: true,
          submissionId: pendingUpload.id,
          uploadUrl,
        }, 200);
      }

      await clearReplaceableSubmissions(
        env,
        versionState.replaceable
      );

      const submissionId = await createSubmission(env, {
        appId,
        developerId: me.id,
        packageName: app.package_name,
        versionName,
        versionCode,
        stagingKey:   stagingKey(app.package_name, versionCode),
        releaseNotes: whatsNew,
      });
      if (!submissionId) return json({ error: "submission_failed" }, 500);

      const uploadUrl = await getPresignedStagingUploadUrl(env, app.package_name, versionCode);
      return json({ ok: true, submissionId, uploadUrl }, 201);
    },
  },
  {
    methods: ["DELETE"],
    match: (path) => path.match(/^\/store\/submissions\/[^/]+$/),
    handle: async ({ env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const submissionId = path.replace("/store/submissions/", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      if (submission.developer_id !== me.id) return forbidden();
      if (submission.status !== SUBMISSION_STATUS.PENDING_UPLOAD) return json({ error: "not_cancellable" }, 409);

      await deleteStagingApk(
        env,
        submission.package_name,
        submission.version_code
      ).catch(() => {});

      await cancelSubmission(env, submissionId);

      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/submissions\/[^/]+\/confirm-upload$/),
    handle: async ({ env, path, requireUser }) => {
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
    },
  },
  {
    methods: ["GET"],
    match: (path) => path.match(/^\/store\/submissions\/[^/]+$/),
    handle: async ({ env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const submissionId = path.replace("/store/submissions/", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      if (submission.developer_id !== me.id && !me.admin) return forbidden();
      return json({ submission });
    },
  },
];
