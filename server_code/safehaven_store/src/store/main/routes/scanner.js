// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { getStoreAppById, getAllLiveApps, getSubmissionsByStatus, SUBMISSION_STATUS } from "../db/index.js";
import { getPresignedDownloadUrl, apkKey, removeVersionFromApp } from "../storage/index.js";
import { nowUnix } from "../../helpers/store_helpers.js";
import { json, unauthorized, isScannerAuth } from "../http/responses.js";

export const routes = [
  {
    methods: ["GET"],
    match: (path) => path === "/internal/store/pending-scans",
    handle: async ({ request, env }) => {
      if (!isScannerAuth(env, request)) return unauthorized();
      const submissions = await getSubmissionsByStatus(env, SUBMISSION_STATUS.PENDING_SCAN);
      const withUrls = await Promise.all(
        submissions.map(async (s) => {
          const app = await getStoreAppById(env, s.app_id);
          return {
            ...s,
            downloadUrl:          await getPresignedDownloadUrl(env, s.staging_key),
            autoTracked:          app ? !!app.auto_tracked : false,
            storedSigningKeyHash: app?.signing_key_hash || null,
          };
        })
      );
      return json({ submissions: withUrls });
    },
  },
  {
    methods: ["GET"],
    match: (path) => path === "/internal/store/rescan-targets",
    handle: async ({ request, env }) => {
      if (!isScannerAuth(env, request)) return unauthorized();

      const liveApps = await getAllLiveApps(env);
      const targets = await Promise.all(
        liveApps
          .filter((row) => row.package_name && Number.isFinite(Number(row.version_code)))
          .map(async (row) => {
            const apkPath = row.apk_key || apkKey(row.package_name, row.version_code);

            return {
              packageName: row.package_name,
              versionName: row.version_name || null,
              versionCode: Number(row.version_code),
              apkPath,
              apkSize: row.apk_size || null,
              apkSha256: row.apk_sha256 || null,
              scannedAt: row.scanned_at || null,
              downloadUrl: await getPresignedDownloadUrl(env, apkPath),
            };
          })
      );

      return json({ targets });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/internal/admin/cleanup-duplicate-versions",
    handle: async ({ request, env }) => {
      if (!isScannerAuth(env, request)) return unauthorized();

      const rows = await env.api_control_db
        .prepare(
          `SELECT sa.package_name, s1.version_code AS inflated_vc, s2.version_code AS real_vc
           FROM store_submissions s1
           JOIN store_submissions s2
             ON s1.app_id = s2.app_id
            AND s1.apk_sha256 = s2.apk_sha256
            AND s1.version_code > s2.version_code
           JOIN store_apps sa ON sa.id = s1.app_id
           WHERE s1.status = 'live'
             AND s2.status = 'live'
           ORDER BY sa.package_name`
        )
        .all();

      const pairs = rows.results || [];
      const cleaned = [];
      const errors = [];

      for (const row of pairs) {
        try {
          await removeVersionFromApp(env, row.package_name, row.inflated_vc);
          await env.api_control_db
            .prepare("UPDATE store_submissions SET status = 'retired', updated_at = ?1 WHERE app_id = (SELECT id FROM store_apps WHERE package_name = ?2) AND version_code = ?3 AND status = 'live'")
            .bind(nowUnix(), row.package_name, row.inflated_vc)
            .run();
          cleaned.push({ packageName: row.package_name, removed: row.inflated_vc, kept: row.real_vc });
        } catch (e) {
          errors.push({ packageName: row.package_name, error: String(e?.message || e) });
        }
      }

      return json({ ok: true, cleaned, errors });
    },
  },
];
