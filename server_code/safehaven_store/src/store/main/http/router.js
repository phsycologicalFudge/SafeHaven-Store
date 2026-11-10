import { routes as publicRoutes } from "../routes/public.js";
import { routes as adminImportsRoutes } from "../routes/admin/imports.js";
import { routes as developerRoutes } from "../routes/developer.js";
import { routes as scannerRoutes } from "../routes/scanner.js";
import { routes as scanResultsRoutes } from "../routes/scan_results.js";
import { routes as submissionsRoutes } from "../routes/submissions.js";
import { routes as adminModerationRoutes } from "../routes/admin/moderation.js";
import { routes as adminMaintenanceRoutes } from "../routes/admin/maintenance.js";
import { routes as trackingRoutes } from "../routes/tracking.js";
import { handleRatingsRoute, handleAdminRatingsRoute } from "../../modules/ratings.js";
import { corsHeaders, json, notFound } from "./responses.js";

const ratingsRoutes = [
  {
    match: () => true,
    handle: ({ request, env, path, method }) => handleRatingsRoute(request, env, path, method),
  },
  {
    match: (path, method) =>
      (method === "GET"    && path === "/admin/store/ratings") ||
      (method === "DELETE" && path.startsWith("/admin/store/ratings/")),
    handle: async ({ request, env, path, method, requireUser }) => {
      const me = await requireUser();
      return handleAdminRatingsRoute(request, env, path, method, me);
    },
  },
];

const routes = [
  ...publicRoutes,
  ...adminImportsRoutes,
  ...developerRoutes,
  ...scannerRoutes,
  ...scanResultsRoutes,
  ...submissionsRoutes,
  ...adminModerationRoutes,
  ...adminMaintenanceRoutes,
  ...trackingRoutes,
  ...ratingsRoutes,
];

const dispatch = async (context) => {
  const { path, method } = context;
  for (const route of routes) {
    if (route.methods && !route.methods.includes(method)) continue;
    if (!route.match(path, method)) continue;
    const response = await route.handle(context);
    if (response) return response;
  }
  return null;
};

export async function handleStore(request, env, auth, ctx) {
  const url    = new URL(request.url);
  const path   = url.pathname;
  const method = request.method;

  const getAuthedUser = async () => {
    if (!auth || typeof auth.getUser !== "function") return null;
    return await auth.getUser(request, env);
  };

  const requireUser = async () => {
    const me = await getAuthedUser();
    return me || null;
  };

  const requireDeveloper = async () => {
    const me = await requireUser();
    if (!me) return null;
    if (!me.developerEnabled) return false;
    return me;
  };

  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const response = await dispatch({ request, env, ctx, url, path, method, requireUser, requireDeveloper });
    return response || notFound();
  } catch (e) {
    console.log(JSON.stringify({
      tag:   "store_error",
      error: String(e?.message || e),
      stack: String(e?.stack   || ""),
    }));
    return json({ error: "internal_error" }, 500);
  }
}
