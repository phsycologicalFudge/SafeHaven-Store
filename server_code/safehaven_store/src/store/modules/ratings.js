import { getIndex, updateAppRating, sha256Hex } from "../storage.js";

const nowUnix = () => Math.floor(Date.now() / 1000);
const db      = (env) => env.api_control_db;

const json       = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json; charset=utf-8" } });
const badRequest = (msg = "bad_request") => json({ error: msg }, 400);
const notFound   = () => json({ error: "not_found" }, 404);

async function checkAndInsertRatingToken(env, hashedToken, packageName) {
  const result = await db(env)
    .prepare("INSERT OR IGNORE INTO store_rating_tokens (hashed_token, package_name, rated_at) VALUES (?1, ?2, ?3)")
    .bind(hashedToken, packageName, nowUnix())
    .run();
  return result.meta.changes === 1;
}

async function upsertAggregatedRating(env, packageName, value) {
  await db(env)
    .prepare(
      "INSERT INTO store_ratings (package_name, rating_sum, rating_count, updated_at) VALUES (?1, ?2, 1, ?3) ON CONFLICT(package_name) DO UPDATE SET rating_sum = rating_sum + ?2, rating_count = rating_count + 1, updated_at = ?3"
    )
    .bind(packageName, value, nowUnix())
    .run();
}

async function getAggregatedRating(env, packageName) {
  return db(env)
    .prepare("SELECT rating_sum, rating_count FROM store_ratings WHERE package_name = ?1 LIMIT 1")
    .bind(packageName)
    .first();
}

async function checkRatingRateLimit(env, hashedIp) {
  const bucket = Math.floor(Date.now() / 1000 / 3600);
  const key    = `${hashedIp}_${bucket}`;
  const row    = await db(env)
    .prepare("SELECT count FROM store_rating_rate_limits WHERE key = ?1 LIMIT 1")
    .bind(key)
    .first();
  if (row && row.count >= 10) return false;
  await db(env)
    .prepare(
      "INSERT INTO store_rating_rate_limits (key, count, expires_at) VALUES (?1, 1, ?2) ON CONFLICT(key) DO UPDATE SET count = count + 1"
    )
    .bind(key, Math.floor(Date.now() / 1000) + 7200)
    .run();
  return true;
}

async function getAllRatings(env) {
  const rows = await db(env)
    .prepare("SELECT package_name, rating_sum, rating_count, updated_at FROM store_ratings ORDER BY rating_count DESC")
    .all();
  return rows.results || [];
}

async function resetAppRatings(env, packageName) {
  await db(env)
    .prepare("DELETE FROM store_ratings WHERE package_name = ?1")
    .bind(packageName)
    .run();
  await db(env)
    .prepare("DELETE FROM store_rating_tokens WHERE package_name = ?1")
    .bind(packageName)
    .run();
}

export async function handleRatingsRoute(request, env, path, method) {
  if (method !== "POST" || path !== "/store/ratings") return null;

  const ct = request.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) return badRequest("json_required");

  let body;
  try { body = await request.json(); } catch { return badRequest("json_required"); }

  const packageName = (body.packageName || "").toString().trim();
  const deviceToken = (body.deviceToken  || "").toString().trim();
  const value       = Number(body.rating);

  if (!packageName)                                        return badRequest("missing_packageName");
  if (!deviceToken)                                        return badRequest("missing_deviceToken");
  if (!Number.isInteger(value) || value < 1 || value > 5) return badRequest("invalid_rating");

  const index = await getIndex(env);
  if (!index.apps.find((a) => a.packageName === packageName)) return notFound();

  const ip       = request.headers.get("cf-connecting-ip") || request.headers.get("x-forwarded-for") || "";
  const hashedIp = await sha256Hex(ip);
  const allowed  = await checkRatingRateLimit(env, hashedIp);
  if (!allowed) return json({ error: "rate_limited" }, 429);

  const hashedToken = await sha256Hex(deviceToken + packageName);
  const inserted    = await checkAndInsertRatingToken(env, hashedToken, packageName);
  if (!inserted) return json({ error: "already_rated" }, 409);

  await upsertAggregatedRating(env, packageName, value);

  const agg = await getAggregatedRating(env, packageName);
  if (agg) await updateAppRating(env, packageName, agg.rating_sum, agg.rating_count);

  return json({ ok: true });
}

export async function handleAdminRatingsRoute(request, env, path, method, me) {
  if (!me || !me.admin) return null;

  if (method === "GET" && path === "/admin/store/ratings") {
    const ratings = await getAllRatings(env);
    return json({ ratings });
  }

  if (method === "DELETE" && path.match(/^\/admin\/store\/ratings\/[^/]+$/)) {
    const packageName = decodeURIComponent(path.replace("/admin/store/ratings/", "")).trim();
    if (!packageName) return badRequest("missing_packageName");
    await resetAppRatings(env, packageName);
    await updateAppRating(env, packageName, 0, 0);
    return json({ ok: true });
  }

  return null;
}
