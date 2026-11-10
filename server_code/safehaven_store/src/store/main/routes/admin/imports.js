import { getStoreAppById } from "../../db/index.js";
import { runGitHubBootstrapImport, runGitHubDirectImport, runGitHubReadmeSweep } from "../../../modules/git_store_job.js";
import { runGitLabDirectImport } from "../../../modules/gitlab_store_job.js";
import { runCodebergDirectImport } from "../../../modules/codeberg_store_job.js";
import { runUpstreamPolls, forcePollApp } from "../../../modules/upstream_orchestrator.js";
import { runFdroidSync, runFdroidUpdateCheck, importOrUpdateFdroidApp } from "../../../modules/fdroid_store_job.js";
import { runIzzySync, runIzzyUpdateCheck, importOrUpdateIzzyApp } from "../../../modules/izzy_store_job.js";
import { nowUnix } from "../../../helpers/store_helpers.js";
import { json, readJson, unauthorized, forbidden, badRequest, notFound, isAdminSecretAuth } from "../../http/responses.js";

const chunkImportRoute = (source, importApp) => ({
  methods: ["POST"],
  match: (path) => path === `/admin/store/${source}-index-chunk`,
  handle: async ({ request, env }) => {
    if (!isAdminSecretAuth(env, request)) return unauthorized();

    const body = await readJson(request);
    if (!body) return badRequest("json_required");

    const stateKey = `${source}_chunk_state`;
    const type     = (body.type || "").toString().trim();

    if (type === "repo") {
      const repoData = body.data || {};
      const totalApps = Number(body.totalApps || 0);
      const totalChunks = Number(body.totalChunks || 0);

      await env.api_control_db
        .prepare("INSERT OR REPLACE INTO sync_state (key, value) VALUES (?1, ?2)")
        .bind(
          stateKey,
          JSON.stringify({
            repo: repoData,
            totalApps,
            totalChunks,
            receivedChunks: [],
            processedApps: 0,
            startedAt: nowUnix(),
          })
        )
        .run();

      return json({ ok: true, message: `Ready to receive ${totalChunks} chunks with ${totalApps} apps` });
    }

    if (type === "apps") {
      const chunkIndex = Number(body.chunkIndex || 0);
      const apps = Array.isArray(body.apps) ? body.apps : [];
      const totalChunks = Number(body.totalChunks || 0);

      const stateRow = await env.api_control_db
        .prepare("SELECT value FROM sync_state WHERE key = ?1")
        .bind(stateKey)
        .first();

      if (!stateRow) return badRequest("repo_metadata_not_initialized");

      const state = JSON.parse(stateRow.value);

      if (state.receivedChunks.includes(chunkIndex)) {
        return json({ ok: true, skipped: true, message: `Chunk ${chunkIndex} already processed` });
      }

      let imported = 0;
      let updated = 0;
      let skipped = 0;
      const errors = [];

      for (const app of apps) {
        try {
          const outcome = await importApp(env, app);
          if (outcome.imported) {
            imported++;
            if (!outcome.isNew) updated++;
          } else if (outcome.skipped) {
            skipped++;
          }
        } catch (e) {
          errors.push({ packageName: app.packageName, error: String(e?.message || e) });
        }
      }

      state.receivedChunks.push(chunkIndex);
      state.processedApps += apps.length;

      await env.api_control_db
        .prepare("UPDATE sync_state SET value = ?1 WHERE key = ?2")
        .bind(JSON.stringify(state), stateKey)
        .run();

      return json({
        ok: true,
        chunkIndex,
        appsReceived: apps.length,
        imported,
        updated,
        skipped,
        errors: errors.slice(0, 5),
        totalReceived: state.receivedChunks.length,
        totalChunks,
      });
    }

    return badRequest("invalid_chunk_type");
  },
});

const indexUploadRoute = (source) => ({
  methods: ["PUT"],
  match: (path) => path === `/admin/store/${source}-index`,
  handle: async ({ request, env }) => {
    if (!isAdminSecretAuth(env, request)) return unauthorized();
    const body = await request.arrayBuffer();
    if (!body.byteLength) return badRequest("empty_body");
    await env.SH_BUCKET.put(`${source}/index-v1.json`, body, {
      httpMetadata: { contentType: "application/json" },
    });
    return json({ ok: true });
  },
});

export const routes = [
  chunkImportRoute("fdroid", importOrUpdateFdroidApp),
  indexUploadRoute("fdroid"),
  chunkImportRoute("izzy", importOrUpdateIzzyApp),
  indexUploadRoute("izzy"),
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/bootstrap-import",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runGitHubBootstrapImport(env);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/fdroid-sync",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runFdroidSync(env);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/fdroid-update-check",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runFdroidUpdateCheck(env);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/izzy-sync",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runIzzySync(env);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/izzy-update-check",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runIzzyUpdateCheck(env);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/readme-sweep",
    handle: async ({ request, env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const body = await readJson(request);
      const rawLimit = Number(body?.limit ?? 50);
      const limit = Number.isFinite(rawLimit)
        ? Math.max(1, Math.min(Math.floor(rawLimit), 100))
        : 100;

      const result = await runGitHubReadmeSweep(env, limit);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/import-repo",
    handle: async ({ request, env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const repoUrl = (body.repoUrl || "").toString().trim();
      if (!repoUrl) return badRequest("repoUrl_required");

      const urlLower   = repoUrl.toLowerCase();
      const isGitLab   = urlLower.includes("gitlab.com");
      const isCodeberg = urlLower.includes("codeberg.org");

      let result;
      if (isGitLab) {
        result = await runGitLabDirectImport(env, { repoUrl, adminImport: true });
      } else if (isCodeberg) {
        result = await runCodebergDirectImport(env, { repoUrl, adminImport: true });
      } else {
        result = await runGitHubDirectImport(env, {
          repoUrl,
          name:         body.name,
          summary:      body.summary,
          description:  body.description,
          iconUrl:      body.iconUrl,
          assetMatch:   body.assetMatch,
          preferredAbi: body.preferredAbi || "arm64-v8a",
          adminImport:  true,
        });
      }

      if (result?.skipped && !result?.imported) {
        return json({ ok: false, result }, 422);
      }

      return json({ ok: true, result }, 201);
    },
  },
  {
    methods: ["POST"],
    match: (path) => path === "/admin/store/upstream-poll",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const result = await runUpstreamPolls(env);
      return json({ ok: true, result });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/admin\/store\/apps\/[^/]+\/force-recheck$/),
    handle: async ({ env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.admin) return forbidden();

      const appId = path.replace("/admin/store/apps/", "").replace("/force-recheck", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();

      const result = await forcePollApp(env, app);
      return json({ ok: true, result });
    },
  },
];
