const CHIP_PALETTES = [
  ["#3B71E8", "#D6E4FF"],
  ["#0F766E", "#CCFBF1"],
  ["#7C3AED", "#EDE9FE"],
  ["#DB2777", "#FCE7F3"],
  ["#D97706", "#FEF3C7"],
  ["#059669", "#D1FAE5"],
  ["#DC2626", "#FEE2E2"],
  ["#0284C7", "#E0F2FE"],
];

export const paletteFor = (seed) => {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) & 0x7fffffff;
  }
  return CHIP_PALETTES[hash % CHIP_PALETTES.length];
};

export const escapeHtml = (value) => {
  return (value || "")
    .toString()
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
};

export const latestVersion = (app) => {
  if (!app.versions || app.versions.length === 0) return null;
  return app.versions.reduce((a, b) => (a.versionCode >= b.versionCode ? a : b));
};

export const displayVersion = (app) => {
  const latest = latestVersion(app);
  if (!latest || !latest.versionName) return "No live version";
  const name = latest.versionName.replace(/^v/i, "");
  return `v${name}`;
};

export const displayRating = (app) => {
  if (!app.ratingCount || app.ratingCount === 0) return "—";
  return app.ratingAvg.toFixed(1);
};

export const developerName = (app) => {
  if (!app.repoUrl) return "";
  try {
    const url = new URL(app.repoUrl.trim());
    const segments = url.pathname.split("/").filter(Boolean);
    return segments.length > 0 ? segments[0] : "";
  } catch {
    return "";
  }
};

export const trustLabel = (app) => {
  if (app.trustLevel === "security_reviewed") return "Security Reviewed";
  if (app.trustLevel === "verified_source") return "Verified Source";
  return "Unverified developer";
};

export const displaySummary = (app) => {
  if (app.summary && app.summary.trim()) return app.summary.trim();
  if (app.description && app.description.trim()) return app.description.trim();
  return "No description available.";
};

export const iconOrFallbackHtml = (app) => {
  const iconUrl = (app.iconUrl || "").trim();
  if (iconUrl) {
    return `<img class="app-icon" src="${escapeHtml(iconUrl)}" alt="${escapeHtml(app.name)}" loading="lazy" />`;
  }
  const [fg, bg] = paletteFor(app.packageName);
  const letter = app.name && app.name.trim() ? app.name.trim()[0].toUpperCase() : "?";
  return `<div class="app-icon-fallback" style="background:${bg};color:${fg}">${escapeHtml(letter)}</div>`;
};

export const SELF_PACKAGE_NAME = "com.colourswift.safehaven";

export const brandIconUrl = (index) => {
  const self = (index.apps || []).find((a) => a.packageName === SELF_PACKAGE_NAME);
  return self?.iconUrl || null;
};

export const selfApp = (index) => {
  return (index.apps || []).find((a) => a.packageName === SELF_PACKAGE_NAME) || null;
};

export const selfDownloadUrl = (index) => {
  const app = selfApp(index);
  const version = app ? latestVersion(app) : null;
  if (!app || !version) return null;

  const safeTitle = (app.name || app.packageName).replace(/[^a-zA-Z0-9._-]/g, "_");
  const versionLabel = version.versionName ? version.versionName.replace(/^v/i, "") : version.versionCode;
  const filename = `${safeTitle}_v${versionLabel}.apk`;

  return `https://api.colourswift.com/store/apps/${encodeURIComponent(app.packageName)}/download/${version.versionCode}?redirect=1&filename=${encodeURIComponent(filename)}`;
};

export const buildLiteIndex = (fullIndex) => {
  const liteApps = (fullIndex.apps || []).map((app) => {
    const latest = latestVersion(app);
    return {
      packageName: app.packageName,
      name: app.name,
      summary: app.summary,
      category: app.category,
      trustLevel: app.trustLevel,
      upstream: app.upstream,
      ratingAvg: app.ratingAvg,
      ratingCount: app.ratingCount,
      iconUrl: app.iconUrl,
      lastUpdated: app.lastUpdated,
      versions: latest ? [latest] : [],
    };
  });

  return {
    version: fullIndex.version,
    timestamp: fullIndex.timestamp,
    categories: fullIndex.categories,
    apps: liteApps,
  };
};
