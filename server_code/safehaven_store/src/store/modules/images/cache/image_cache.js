import { getPresignedDownloadUrl } from "../../../storage.js";

const ALLOWED_PREFIX = "images/";
const DEFAULT_CONTENT_TYPE = "image/png";
const EDGE_TTL_SECONDS = 2592000;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

const isSafeKey = (key) =>
  !!key &&
  key.startsWith(ALLOWED_PREFIX) &&
  !key.includes("..") &&
  !key.includes("\\");

export async function handleImageCacheRoute(request, env, ctx, rawKey) {
  if (request.method !== "GET" && request.method !== "HEAD") return null;

  let key;
  try {
    key = decodeURIComponent((rawKey || "").toString()).replace(/^\/+/, "").trim();
  } catch {
    return new Response(null, { status: 400 });
  }

  if (!isSafeKey(key)) return new Response(null, { status: 400 });

  const cache = caches.default;
  const cacheKey = new Request(new URL(request.url).toString(), { method: "GET" });

  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  let originRes;
  try {
    const signedUrl = await getPresignedDownloadUrl(env, key, 300);
    originRes = await fetch(signedUrl);
  } catch {
    return new Response(null, { status: 502 });
  }

  if (originRes.status === 404) return new Response(null, { status: 404 });
  if (!originRes.ok) return new Response(null, { status: 502 });

  const body = await originRes.arrayBuffer();
  if (body.byteLength > MAX_IMAGE_BYTES) return new Response(null, { status: 502 });

  const contentType = originRes.headers.get("content-type") || DEFAULT_CONTENT_TYPE;

  const response = new Response(body, {
    status: 200,
    headers: {
      "content-type": contentType,
      "cache-control": `public, max-age=${EDGE_TTL_SECONDS}, immutable`,
      "access-control-allow-origin": "*",
    },
  });

  const put = cache.put(cacheKey, response.clone());
  if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(put);
  else await put;

  return response;
}