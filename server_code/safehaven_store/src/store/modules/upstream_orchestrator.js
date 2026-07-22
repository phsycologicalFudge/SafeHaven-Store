import { nowUnix } from "../helpers/store_helpers.js";
import { pollGitHubApp } from "./git_store_job.js";
import { pollGitLabApp } from "./gitlab_store_job.js";
import { pollCodebergApp } from "./codeberg_store_job.js";
import { importOrUpdateFdroidApp, pickBestVersion as pickBestFdroidVersion } from "./fdroid_store_job.js";
import { importOrUpdateIzzyApp, pickBestVersion as pickBestIzzyVersion } from "./izzy_store_job.js";

const POLL_INTERVAL_SEC = 21600;
const POLL_PAGE_SIZE = 200;
const DEFAULT_POLL_TIME_BUDGET_MS = 300_000;

const setAppLastRepoCheck = (env, appId) =>
  env.api_control_db
    .prepare("UPDATE store_apps SET last_repo_check = ?2 WHERE id = ?1")
    .bind((appId || "").toString().trim(), nowUnix())
    .run();

const getAppsForPolling = async (env) => {
  const cutoff = nowUnix() - POLL_INTERVAL_SEC;
  const rows = await env.api_control_db
    .prepare(
      `SELECT * FROM store_apps
       WHERE status = 'active'
         AND (upstream IS NULL OR upstream NOT IN ('fdroid', 'izzyondroid'))
         AND (last_repo_check IS NULL OR last_repo_check <= ?1)
         AND (
           (auto_tracked = 1 AND claimed = 0)
           OR (claimed = 1 AND (submission_mode_manual IS NULL OR submission_mode_manual = 0))
         )
       ORDER BY last_repo_check ASC
       LIMIT ?2`
    )
    .bind(cutoff, POLL_PAGE_SIZE)
    .all();
  return rows.results || [];
};

export const detectPlatform = (repoUrl) => {
  const url = (repoUrl || "").toString().toLowerCase();
  if (url.includes("github.com"))   return "github";
  if (url.includes("gitlab.com"))   return "gitlab";
  if (url.includes("codeberg.org")) return "codeberg";
  return null;
};

const pollFdroidApp = async (env, app) => {
  const obj = await env.SH_BUCKET.get("fdroid/index-v1.json");
  if (!obj) return null;
  const index = await obj.json();

  const versions = index.packages?.[app.package_name];
  if (!Array.isArray(versions) || !versions.length) return null;

  const best = pickBestFdroidVersion(versions);
  if (!best) return null;

  const appMeta = (index.apps || []).find((a) => a.packageName === app.package_name) || {};
  const fdroidApp = { packageName: app.package_name, ...appMeta, ...best };

  const outcome = await importOrUpdateFdroidApp(env, fdroidApp);
  return !!outcome?.imported;
};

const pollIzzyApp = async (env, app) => {
  const obj = await env.SH_BUCKET.get("izzy/index-v1.json");
  if (!obj) return null;
  const index = await obj.json();

  const versions = index.packages?.[app.package_name];
  if (!Array.isArray(versions) || !versions.length) return null;

  const best = pickBestIzzyVersion(versions);
  if (!best) return null;

  const appMeta = (index.apps || []).find((a) => a.packageName === app.package_name) || {};
  const izzyApp = { packageName: app.package_name, ...appMeta, ...best };

  const outcome = await importOrUpdateIzzyApp(env, izzyApp);
  return !!outcome?.imported;
};

const pollByUpstream = async (env, app) => {
  switch (app.upstream) {
    case "fdroid":
      return pollFdroidApp(env, app);
    case "izzyondroid":
      return pollIzzyApp(env, app);
    case "github":
      return pollGitHubApp(env, app);
    case "gitlab":
      return pollGitLabApp(env, app);
    case "codeberg":
      return pollCodebergApp(env, app);
    default:
      return undefined;
  }
};

export async function forcePollApp(env, app) {
  const upstream = app.upstream || null;

  if (!upstream) {
    return { checked: true, submitted: false, skipped: true, reason: "unknown_upstream", upstream: null };
  }

  try {
    const queued = await pollByUpstream(env, app);

    if (queued === undefined) {
      return { checked: true, submitted: false, skipped: true, reason: "unsupported_upstream", upstream };
    }

    await setAppLastRepoCheck(env, app.id);

    return { checked: true, submitted: !!queued, skipped: false, upstream };
  } catch (e) {
    await setAppLastRepoCheck(env, app.id).catch(() => {});
    return { checked: true, submitted: false, skipped: false, upstream, error: String(e?.message || e) };
  }
}

export async function runUpstreamPolls(env, options = {}) {
  const timeBudgetMs = options.timeBudgetMs ?? DEFAULT_POLL_TIME_BUDGET_MS;
  const deadline = Date.now() + timeBudgetMs;

  const results = {
    checked:   0,
    submitted: 0,
    skipped:   0,
    errors:    [],
  };

  while (Date.now() < deadline) {
    const apps = await getAppsForPolling(env);
    if (!apps.length) break;

    for (const app of apps) {
      if (Date.now() >= deadline) break;

      results.checked++;

      try {
        const queued = await pollByUpstream(env, app);

        if (queued === undefined) {
          results.skipped++;
          await setAppLastRepoCheck(env, app.id);
          continue;
        }

        await setAppLastRepoCheck(env, app.id);
        if (queued) results.submitted++;

      } catch (e) {
        results.errors.push({
          appId:    app.id,
          upstream: app.upstream,
          repoUrl:  app.repo_url,
          error:    String(e?.message || e),
        });
        await setAppLastRepoCheck(env, app.id).catch(() => {});
      }
    }

    if (apps.length < POLL_PAGE_SIZE) break;
  }

  console.log(JSON.stringify({
    tag:       "upstream_poll_complete",
    checked:   results.checked,
    submitted: results.submitted,
    skipped:   results.skipped,
    errors:    results.errors.length,
  }));

  return results;
}