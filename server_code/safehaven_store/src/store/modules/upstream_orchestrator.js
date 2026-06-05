import { nowUnix } from "../helpers/store_helpers.js";
import { pollGitHubApp } from "./git_store_job.js";
import { pollGitLabApp } from "./gitlab_store_job.js";
import { pollCodebergApp } from "./codeberg_store_job.js";

const POLL_INTERVAL_SEC = 21600;

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
       WHERE auto_tracked = 1
         AND status = 'active'
         AND (upstream IS NULL OR upstream NOT IN ('fdroid'))
         AND (last_repo_check IS NULL OR last_repo_check <= ?1)
       ORDER BY last_repo_check ASC
       LIMIT 50`
    )
    .bind(cutoff)
    .all();
  return rows.results || [];
};

const detectPlatform = (repoUrl) => {
  const url = (repoUrl || "").toString().toLowerCase();
  if (url.includes("github.com"))   return "github";
  if (url.includes("gitlab.com"))   return "gitlab";
  if (url.includes("codeberg.org")) return "codeberg";
  return null;
};

export async function runUpstreamPolls(env) {
  const apps    = await getAppsForPolling(env);
  const results = {
    checked:   0,
    submitted: 0,
    skipped:   0,
    errors:    [],
  };

  for (const app of apps) {
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

  console.log(JSON.stringify({
    tag:       "upstream_poll_complete",
    checked:   results.checked,
    submitted: results.submitted,
    skipped:   results.skipped,
    errors:    results.errors.length,
  }));

  return results;
}
