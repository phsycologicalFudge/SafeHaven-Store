import { nowUnix } from "../helpers/store_helpers.js";
import { pollGitHubApp } from "./git_store_job.js";
import { pollGitLabApp } from "./gitlab_store_job.js";
import { pollCodebergApp } from "./codeberg_store_job.js";

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
         AND (upstream IS NULL OR upstream NOT IN ('fdroid'))
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

export async function forcePollApp(env, app) {
  const platform = detectPlatform(app.repo_url);

  if (!platform) {
    return { checked: true, submitted: false, skipped: true, reason: "unsupported_platform", platform: null };
  }

  try {
    let queued = null;

    if (platform === "github") {
      queued = await pollGitHubApp(env, app);
    } else if (platform === "gitlab") {
      queued = await pollGitLabApp(env, app);
    } else if (platform === "codeberg") {
      queued = await pollCodebergApp(env, app);
    }

    await setAppLastRepoCheck(env, app.id);

    return { checked: true, submitted: !!queued, skipped: false, platform };
  } catch (e) {
    await setAppLastRepoCheck(env, app.id).catch(() => {});
    return { checked: true, submitted: false, skipped: false, platform, error: String(e?.message || e) };
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
      const platform = detectPlatform(app.repo_url);

      try {
        let queued = null;

        if (platform === "github") {
          queued = await pollGitHubApp(env, app);
        } else if (platform === "gitlab") {
          queued = await pollGitLabApp(env, app);
        } else if (platform === "codeberg") {
          queued = await pollCodebergApp(env, app);
        } else {
          results.skipped++;
          await setAppLastRepoCheck(env, app.id);
          continue;
        }

        await setAppLastRepoCheck(env, app.id);
        if (queued) results.submitted++;

      } catch (e) {
        results.errors.push({
          appId:    app.id,
          platform,
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