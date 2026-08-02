import { getLiteIndex } from "../data/index_reader.ts";

const MAX_RESULTS = 50;

export const handleSearchRoute = async (request, env, path) => {
  if (path !== "/search") return null;

  const params = new URL(request.url).searchParams;
  const q = (params.get("q") || "").trim().toLowerCase();
  const cat = (params.get("cat") || "").trim().toLowerCase();
  const minRating = parseFloat(params.get("rating")) || 0;

  if (!q && !cat && !minRating) {
    return json({ results: [] });
  }

  const index = await getLiteIndex(env);
  const results = [];

  for (const app of index.apps || []) {
    if (!app.versions || app.versions.length === 0) continue;
    if (cat && (app.category || "").trim().toLowerCase() !== cat) continue;
    if (minRating && (app.ratingAvg || 0) < minRating) continue;
    if (q) {
      const name = (app.name || "").toLowerCase();
      const pkg = (app.packageName || "").toLowerCase();
      if (!name.includes(q) && !pkg.includes(q)) continue;
    }
    results.push({
      n: app.name,
      p: app.packageName,
      i: app.iconUrl || "",
      r: app.ratingCount > 0 ? Number(app.ratingAvg).toFixed(1) : "",
    });
    if (results.length >= MAX_RESULTS) break;
  }

  return json({ results });
};

const json = (body) =>
  new Response(JSON.stringify(body), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=60",
    },
  });
