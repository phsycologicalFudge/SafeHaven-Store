import { getIndex } from "../../storage.js";
import { buildLiteIndex } from "../lib/shared.ts";

export const getStorefrontIndex = async (env) => {
  if (env.STORE_INDEX_KV) {
    const cached = await env.STORE_INDEX_KV.get("index");
    if (cached) return JSON.parse(cached);
  }

  const index = await getIndex(env);

  if (env.STORE_INDEX_KV) {
    await env.STORE_INDEX_KV.put("index", JSON.stringify(index));
    await env.STORE_INDEX_KV.put("index_timestamp", String(index.timestamp));
  }

  return index;
};

export const getAppDetail = async (env, packageName) => {
  const lite = await getLiteIndex(env);
  const liteEntry = lite.apps.find((a) => a.packageName === packageName);

  if (!liteEntry) return { app: null, lite };

  const cacheKey = `app_full:${packageName}`;

  if (env.STORE_INDEX_KV) {
    const cached = await env.STORE_INDEX_KV.get(cacheKey);
    if (cached) {
      const parsed = JSON.parse(cached);
      if (parsed.lastUpdated === liteEntry.lastUpdated) {
        return { app: parsed, lite };
      }
    }
  }

  const fullIndex = await getStorefrontIndex(env);
  const fullApp = fullIndex.apps.find((a) => a.packageName === packageName) || null;

  if (fullApp && env.STORE_INDEX_KV) {
    await env.STORE_INDEX_KV.put(cacheKey, JSON.stringify(fullApp));
  }

  return { app: fullApp, lite };
};

export const getLiteIndex = async (env) => {
  if (env.STORE_INDEX_KV) {
    const currentTimestamp = await env.STORE_INDEX_KV.get("index_timestamp");
    const cachedLite = await env.STORE_INDEX_KV.get("index_lite");

    if (cachedLite && currentTimestamp) {
      const parsed = JSON.parse(cachedLite);
      if (String(parsed.timestamp) === currentTimestamp) {
        return parsed;
      }
    }
  }

  const fullIndex = await getStorefrontIndex(env);
  const lite = buildLiteIndex(fullIndex);

  if (env.STORE_INDEX_KV) {
    await env.STORE_INDEX_KV.put("index_lite", JSON.stringify(lite));
    await env.STORE_INDEX_KV.put("index_timestamp", String(fullIndex.timestamp));
  }

  return lite;
};
