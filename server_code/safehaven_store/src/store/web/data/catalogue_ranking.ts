import { latestVersion } from "../lib/shared.ts";

const ratingScore = (app) => {
  if (!app.ratingCount || app.ratingCount <= 0 || !app.ratingAvg || app.ratingAvg <= 0) return 0;
  return app.ratingAvg * (Math.log(app.ratingCount + 1) / Math.LN10);
};

const trendingScore = (app) => {
  const base = ratingScore(app);
  const added = latestVersion(app)?.added;
  if (!added || added <= 0) return 0;

  const nowSeconds = Math.floor(Date.now() / 1000);
  const ageDays = (nowSeconds - added) / 86400;
  if (ageDays <= 0) return base;

  return base / Math.pow(ageDays + 2, 1.5);
};

const dayOfYearSeed = (date = new Date()) => {
  const start = Date.UTC(date.getUTCFullYear(), 0, 0);
  const diff = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) - start;
  return Math.floor(diff / 86400000);
};

const seededShuffle = (items, seed) => {
  const arr = [...items];
  let s = seed;
  const rand = () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
};

const SELF_PACKAGE_PREFIX = "com.colourswift.";

export const topCharts = (apps, limit = 10) => {
  const shuffled = seededShuffle(apps, dayOfYearSeed());
  const sorted = shuffled.sort((a, b) => trendingScore(b) - trendingScore(a));

  for (let i = 0; i < 3 && i < sorted.length; i++) {
    if (sorted[i].packageName.startsWith(SELF_PACKAGE_PREFIX)) {
      for (let j = i + 1; j < sorted.length; j++) {
        if (!sorted[j].packageName.startsWith(SELF_PACKAGE_PREFIX)) {
          [sorted[i], sorted[j]] = [sorted[j], sorted[i]];
          break;
        }
      }
    }
  }

  return sorted.slice(0, limit);
};

export const newArrivals = (apps, limit = 10) => {
  return [...apps]
    .sort((a, b) => {
      const addedA = latestVersion(a)?.added || 0;
      const addedB = latestVersion(b)?.added || 0;
      return addedB - addedA;
    })
    .slice(0, limit);
};

export const topInCategory = (apps, categoryKey, limit = 10) => {
  const normalised = categoryKey.trim().toLowerCase();
  const inCategory = apps.filter((a) => (a.category || "").trim().toLowerCase() === normalised);
  return inCategory.sort((a, b) => ratingScore(b) - ratingScore(a)).slice(0, limit);
};

export const dailyShuffledCategoryKeys = (categories) => {
  const keys = Object.keys(categories || {});
  return seededShuffle(keys, dayOfYearSeed());
};
