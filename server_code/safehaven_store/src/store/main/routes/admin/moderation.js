// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { getStoreAppById, getAllStoreApps, setAppSigningKeyHash, setAppTrustLevel, setAppStatus, setAppCategory, getSubmissionById, getSubmissionsByStatus, rejectSubmission, SUBMISSION_STATUS, APP_STATUS, TRUST_LEVEL } from "../../db/index.js";
import { addOrUpdateApp, removeApp, CATEGORIES } from "../../storage/index.js";
import { nowUnix, buildIndexAppEntry } from "../../../helpers/store_helpers.js";
import { json, readJson, unauthorized, forbidden, badRequest, notFound } from "../../http/responses.js";
import { approveAndPublish } from "../../services/publish.js";

export const routes = [
  {
    methods: ["GET"],
    match: (path) => path === "/admin/store/submissions",
    handle: async ({ env, url, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const statusFilter = url.searchParams.get("status") || SUBMISSION_STATUS.PENDING_REVIEW;
      const submissions  = await getSubmissionsByStatus(env, statusFilter);
      return json({ submissions });
    },
  },
  {
    methods: ["GET"],
    match: (path) => path === "/admin/store/apps",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me)       return unauthorized();
      if (!me.admin) return forbidden();
      const apps = await getAllStoreApps(env);
      return json({ apps });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/submissions\/[^/]+\/approve$/),
    handle: async ({ env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const submissionId = path.replace("/admin/store/submissions/", "").replace("/approve", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      if (submission.status !== SUBMISSION_STATUS.PENDING_REVIEW) {
        return json({ error: "invalid_status" }, 409);
      }
      await approveAndPublish(env, submission, me.id);
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/submissions\/[^/]+\/reject$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const submissionId = path.replace("/admin/store/submissions/", "").replace("/reject", "").trim();
      const submission   = await getSubmissionById(env, submissionId);
      if (!submission) return notFound();
      const body   = await readJson(request);
      const reason = (body?.reason || "").toString().trim() || null;
      await rejectSubmission(env, submissionId, reason, me.id);
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/apps\/[^/]+\/trust-level$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();
      const appId      = path.replace("/admin/store/apps/", "").replace("/trust-level", "").trim();
      const body       = await readJson(request);
      if (!body) return badRequest("json_required");
      const trustLevel = body.trustLevel === null
        ? null
        : (body.trustLevel || "").toString().trim();

      if (trustLevel !== null && !Object.values(TRUST_LEVEL).includes(trustLevel)) {
        return badRequest("invalid_trustLevel");
      }
      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();
      await setAppTrustLevel(env, appId, trustLevel);
      if (app.status === APP_STATUS.ACTIVE) {
        await addOrUpdateApp(env, { ...buildIndexAppEntry(env, app), trustLevel });
      }
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/apps\/[^/]+\/status$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const appId = path.replace("/admin/store/apps/", "").replace("/status", "").trim();
      const body  = await readJson(request);
      if (!body) return badRequest("json_required");

      const status = (body.status || "").toString().trim();
      if (!Object.values(APP_STATUS).includes(status)) return badRequest("invalid_status");

      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();

      if (status === APP_STATUS.REMOVED) {
        await removeApp(env, app.package_name);

        await env.api_control_db
          .prepare("DELETE FROM store_submissions WHERE app_id = ?1")
          .bind(appId)
          .run();

        await env.api_control_db
          .prepare("DELETE FROM store_apps WHERE id = ?1")
          .bind(appId)
          .run();

        return json({ ok: true, removed: true });
      }

      await setAppStatus(env, appId, status);

      if (status === APP_STATUS.SUSPENDED) {
        await removeApp(env, app.package_name);
      }

      if (status === APP_STATUS.ACTIVE) {
        const updatedApp = await getStoreAppById(env, appId);
        if (updatedApp) {
          const liveSubmission = await env.api_control_db
            .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND status = 'live' LIMIT 1")
            .bind(appId)
            .first();
          if (liveSubmission) {
            await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
          }
        }
      }

      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/apps\/[^/]+\/category$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me)       return unauthorized();
      if (!me.admin) return forbidden();
      const appId    = path.replace("/admin/store/apps/", "").replace("/category", "").trim();
      const body     = await readJson(request);
      if (!body) return badRequest("json_required");
      const category = (body.category || "").toString().trim() || null;
      if (category && !Object.keys(CATEGORIES).includes(category)) return badRequest("invalid_category");
      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();
      await setAppCategory(env, appId, category);
      if (app.status === APP_STATUS.ACTIVE) {
        await addOrUpdateApp(env, { ...buildIndexAppEntry(env, app), category });
      }
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/apps\/[^/]+\/override-hash$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const appId = path.replace("/admin/store/apps/", "").replace("/override-hash", "").trim();
      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const newHash = (body.newHash || "").toString().trim();
      const reason = (body.reason || "").toString().trim();

      if (!newHash) return badRequest("newHash_required");

      const app = await getStoreAppById(env, appId);
      if (!app) return notFound();

      const oldHash = app.signing_key_hash || "";

      await setAppSigningKeyHash(env, appId, newHash);
      await env.api_control_db.prepare("UPDATE store_apps SET signing_flag = NULL WHERE id = ?1").bind(appId).run();
      await env.api_control_db.prepare(
        "INSERT INTO store_hash_history (app_id, old_hash, new_hash, reason, updated_by, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
      ).bind(appId, oldHash, newHash, reason, me.id, nowUnix()).run();

      return json({ ok: true, oldHash, newHash });
    },
  },
];
