import { getAllStoreApps } from "../../db/index.js";
import { getIndex, putIndex, publicImageUrl, putImageObject, CATEGORIES, updateAppRating } from "../../storage/index.js";
import { normaliseIcon } from "../../../modules/images/icon_normalise.js";
import { normaliseScreenshot } from "../../../modules/images/screenshot_normalise.js";
import { nowUnix, parseScreenshots } from "../../../helpers/store_helpers.js";
import { json, readJson, unauthorized, forbidden } from "../../http/responses.js";

export const routes = [
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/clear-index",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      await putIndex(env, {
        version: 1,
        timestamp: nowUnix(),
        categories: CATEGORIES,
        apps: [],
      });

      return json({ ok: true, cleared: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/repopulate-ratings",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const rows = await env.api_control_db
        .prepare("SELECT package_name, rating_sum, rating_count FROM store_ratings WHERE rating_count > 0")
        .all();

      const ratings = rows.results || [];
      for (const row of ratings) {
        await updateAppRating(env, row.package_name, row.rating_sum, row.rating_count);
      }

      return json({ ok: true, restored: ratings.length });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/backfill-signing-hashes",
    handle: async ({ request, env }) => {
      const provided = (request.headers.get("authorization") || "").trim();
      if (!provided || provided !== (env.SH_ADMIN_SECRET || "").trim()) return unauthorized();

      const rows = await env.api_control_db
        .prepare("SELECT package_name, signing_key_hash FROM store_apps WHERE signing_key_hash IS NOT NULL AND package_name IS NOT NULL")
        .all();

      const hashByPackage = new Map((rows.results || []).map((r) => [r.package_name, r.signing_key_hash]));

      const index = await getIndex(env);
      let patched = 0;

      for (const entry of index.apps) {
        const hash = hashByPackage.get(entry.packageName);
        if (hash && entry.signingKeyHash !== hash) {
          entry.signingKeyHash = hash;
          patched++;
        }
      }

      if (patched > 0) await putIndex(env, index);

      return json({ ok: true, patched, totalIndexApps: index.apps.length, totalWithHash: hashByPackage.size });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/normalise-images",
    handle: async ({ request, env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const body   = await readJson(request).catch(() => null) || {};
      const offset = Math.max(0, Number(body.offset) || 0);

      const DEADLINE_MS = 25_000;
      const startedAt  = Date.now();

      const apps = await getAllStoreApps(env);

      const results = {
        icons:            { processed: 0, skipped: 0, failed: 0 },
        screenshots:      { processed: 0, skipped: 0, failed: 0 },
        errors:           [],
        totalIcons:       { processed: Number(body.totalIcons?.processed       || 0), skipped: Number(body.totalIcons?.skipped       || 0), failed: Number(body.totalIcons?.failed       || 0) },
        totalScreenshots: { processed: Number(body.totalScreenshots?.processed || 0), skipped: Number(body.totalScreenshots?.skipped || 0), failed: Number(body.totalScreenshots?.failed || 0) },
        offset:           null,
        appsTotal:        apps.length,
        appsChecked:      0,
      };

      for (let i = offset; i < apps.length; i++) {
        if (Date.now() - startedAt >= DEADLINE_MS) {
          results.offset = i;
          break;
        }

        const app = apps[i];
        results.appsChecked++;

        if (!app.package_name) continue;

        if (app.icon_key) {
          try {
            const res = await fetch(publicImageUrl(env, app.icon_key));
            if (!res.ok) {
              results.icons.skipped++;
              console.log(JSON.stringify({ tag: "normalise_skip", appId: app.id, slot: "icon", status: res.status }));
            } else {
              const normed = await normaliseIcon(new Uint8Array(await res.arrayBuffer()));
              await putImageObject(env, app.package_name, "icon", normed, "image/png");
              results.icons.processed++;
              console.log(JSON.stringify({ tag: "normalise_ok", appId: app.id, packageName: app.package_name, slot: "icon" }));
            }
          } catch (e) {
            results.icons.failed++;
            const msg = String(e?.message || e);
            results.errors.push({ appId: app.id, packageName: app.package_name, slot: "icon", error: msg });
            console.log(JSON.stringify({ tag: "normalise_fail", appId: app.id, packageName: app.package_name, slot: "icon", error: msg }));
          }
        } else {
          results.icons.skipped++;
        }

        const screenshotKeys = parseScreenshots(app.screenshots_json);
        for (let s = 0; s < screenshotKeys.length; s++) {
          if (Date.now() - startedAt >= DEADLINE_MS) {
            results.offset = i;
            break;
          }
          const slot = `screenshot_${s + 1}`;
          try {
            const res = await fetch(publicImageUrl(env, screenshotKeys[s]));
            if (!res.ok) {
              results.screenshots.skipped++;
              console.log(JSON.stringify({ tag: "normalise_skip", appId: app.id, slot, status: res.status }));
              continue;
            }
            const normed = await normaliseScreenshot(new Uint8Array(await res.arrayBuffer()));
            await putImageObject(env, app.package_name, slot, normed, "image/png");
            results.screenshots.processed++;
            console.log(JSON.stringify({ tag: "normalise_ok", appId: app.id, packageName: app.package_name, slot }));
          } catch (e) {
            results.screenshots.failed++;
            const msg = String(e?.message || e);
            results.errors.push({ appId: app.id, packageName: app.package_name, slot, error: msg });
            console.log(JSON.stringify({ tag: "normalise_fail", appId: app.id, packageName: app.package_name, slot, error: msg }));
          }
        }

        if (results.offset !== null) break;
      }

      results.totalIcons.processed       += results.icons.processed;
      results.totalIcons.skipped         += results.icons.skipped;
      results.totalIcons.failed          += results.icons.failed;
      results.totalScreenshots.processed += results.screenshots.processed;
      results.totalScreenshots.skipped   += results.screenshots.skipped;
      results.totalScreenshots.failed    += results.screenshots.failed;

      console.log(JSON.stringify({ tag: "normalise_batch", offset, nextOffset: results.offset, elapsed: Date.now() - startedAt }));

      return json({ ok: true, ...results });
    },
  },
];
