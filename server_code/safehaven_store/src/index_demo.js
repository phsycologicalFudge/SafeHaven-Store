import { 
  handleStore, 
  runStoreAutoApprovals, 
  runGitHubBootstrapImport, 
  runGitHubReadmeSweep, 
  runFdroidSync, 
  runUnclaimedRepoPolls 
} from "./store/store.js";
import { demoAuth } from "./store/auth_demo.js";
import { renderDashboardHtml } from "./store/web/dashboard.js";

const html = (body, status = 200) =>
  new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });

export default {
  async fetch(request, env, ctx) {
    const url    = new URL(request.url);
    const path   = url.pathname;
    const method = request.method;

    if (method === "GET" && (path === "/" || path === "/admin")) {
      return html(renderDashboardHtml());
    }

    return handleStore(request, env, demoAuth);
  },

  async scheduled(event, env, ctx) {
    switch (event.cron) {
      case "0 * * * *":
        ctx.waitUntil(runStoreAutoApprovals(env));
        ctx.waitUntil(runUnclaimedRepoPolls(env));
        ctx.waitUntil(runUpstreamPolls(env));
        break;
      case "0 */6 * * *":
        ctx.waitUntil(runGitHubReadmeSweep(env));
        ctx.waitUntil(runFdroidSync(env));
        break;
      case "0 3 3 * *":
        ctx.waitUntil(runGitHubBootstrapImport(env));
        break;
    }
  },
};