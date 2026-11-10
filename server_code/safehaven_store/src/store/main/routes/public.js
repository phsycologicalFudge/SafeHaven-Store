// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { getIndex, getPresignedDownloadUrl, apkKey, CATEGORIES, getChangelog } from "../storage/index.js";
import { handleImageCacheRoute } from "../../modules/images/cache/image_cache.js";
import { nowUnix } from "../../helpers/store_helpers.js";
import { corsHeaders, json, badRequest, notFound } from "../http/responses.js";

export const routes = [
  {
    methods: ["GET", "HEAD"],
    match: (path) => path.startsWith("/store/img/"),
    handle: async ({ request, env, ctx, path }) => {
      const imgRes = await handleImageCacheRoute(request, env, ctx, path.replace("/store/img/", ""));
      if (imgRes) return imgRes;
    },
  },
  {
    methods: ["GET"],
    match: (path) => path === "/store/sync",
    handle: async ({ env, url }) => {
      const since = Number(url.searchParams.get("since") || 0);
      const now = nowUnix();
      const SEVEN_DAYS_SEC = 7 * 24 * 60 * 60;

      if (!since || now - since > SEVEN_DAYS_SEC) {
        return json({
          action: "full",
          url: "/store/index.json"
        });
      }

      let changelog;
      try {
        changelog = await getChangelog(env);
      } catch {
        changelog = { events: [] };
      }

      const finalUpdates = new Map();
      const finalRemoves = new Set();
      let latestTimestamp = since;

      for (const event of changelog.events) {
        if (event.timestamp > since) {
          latestTimestamp = Math.max(latestTimestamp, event.timestamp);
          
          for (const pkg of event.removes) {
            finalRemoves.add(pkg);
            finalUpdates.delete(pkg);
          }
          
          for (const app of event.updates) {
            finalUpdates.set(app.packageName, app);
            finalRemoves.delete(app.packageName);
          }
        }
      }

      return json({
        action: "patch",
        timestamp: latestTimestamp,
        updates: Array.from(finalUpdates.values()).filter(
          (a) => Array.isArray(a.versions) && a.versions.length > 0
        ),
        removes: Array.from(finalRemoves),
        });
    },
  },
  {
    methods: ["GET"],
    match: (path) => path === "/store/index.json",
    handle: async ({ env }) => {
      const index = await getIndex(env);
      const filtered = {
        ...index,
        apps: (index.apps || []).filter((a) => Array.isArray(a.versions) && a.versions.length > 0),
      };
      return new Response(JSON.stringify(filtered), {
        headers: {
          "content-type":  "application/json; charset=utf-8",
          "cache-control": "public, max-age=60",
          ...corsHeaders,
        },
      });
    },
  },
  {
    methods: ["GET"],
    match: (path) => path.startsWith("/store/catalog/"),
    handle: async ({ env, path }) => {
      const packageName = decodeURIComponent(path.replace("/store/catalog/", "")).trim();
      if (!packageName) return notFound();
      const index = await getIndex(env);
      const app   = index.apps.find((a) => a.packageName === packageName);
      if (!app) return notFound();
      return json(app);
    },
  },
  {
    methods: ["GET"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/download\/[^/]+$/),
    handle: async ({ request, env, path }) => {
      const parts       = path.replace("/store/apps/", "").split("/download/");
      const packageName = decodeURIComponent(parts[0] || "").trim();
      const versionCode = Number(parts[1] || "");
      if (!packageName || !Number.isFinite(versionCode)) return badRequest("invalid_params");
      const dlUrl = await getPresignedDownloadUrl(env, apkKey(packageName, versionCode), 300);
      const params = new URL(request.url).searchParams;
      const wantsRedirect = params.get("redirect") === "1";
      if (wantsRedirect) {
        const filename = (params.get("filename") || "").trim();
        if (filename) {
          const upstream = await fetch(dlUrl);
          if (!upstream.ok) return new Response("download_failed", { status: 502 });
          const headers = new Headers(upstream.headers);
          headers.set("content-disposition", `attachment; filename="${filename}"`);
          headers.set("content-type", "application/vnd.android.package-archive");
          return new Response(upstream.body, { status: 200, headers });
        }
        return new Response(null, { status: 302, headers: { location: dlUrl } });
      }
      return json({ url: dlUrl });
    },
  },
  {
    methods: ["GET"],
    match: (path) => path === "/store/categories",
    handle: async () => {
      return json({ categories: CATEGORIES });
    },
  },
];
