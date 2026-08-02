import {
  escapeHtml,
  iconOrFallbackHtml,
  displayVersion,
  displayRating,
  developerName,
  trustLabel,
  displaySummary,
  latestVersion,
  brandIconUrl,
} from "../lib/shared.ts";
import { renderMarkdown } from "../lib/markdown.ts";
import { footerHtml } from "../components/footer.ts";
import { headerHtml, themeHeadScript, themeScript } from "../components/header.ts";

export const renderAppPage = (app, baseUrl, index) => {
  const brandIcon = brandIconUrl(index);
  const pageUrl = `${baseUrl}/app/${encodeURIComponent(app.packageName)}`;
  const summary = displaySummary(app);
  const version = latestVersion(app);
  const safeTitle = (app.name || app.packageName).replace(/[^a-zA-Z0-9._-]/g, "_");
  const versionLabel = version.versionName ? version.versionName.replace(/^v/i, "") : version.versionCode;
  const downloadFilename = `${safeTitle}_v${versionLabel}.apk`;
  const downloadUrl = version
    ? `https://api.colourswift.com/store/apps/${encodeURIComponent(app.packageName)}/download/${version.versionCode}?redirect=1&filename=${encodeURIComponent(downloadFilename)}`
    : null;

  const screenshotsHtml = (app.screenshots || [])
    .map((s) => `<img src="${escapeHtml(s)}" alt="${escapeHtml(app.name)} screenshot" loading="lazy" />`)
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${escapeHtml(app.name)} - SafeHaven Store</title>
<meta name="description" content="${escapeHtml(summary)}" />
<meta property="og:title" content="${escapeHtml(app.name)}" />
<meta property="og:description" content="${escapeHtml(summary)}" />
<meta property="og:image" content="${escapeHtml(app.iconUrl || "")}" />
<meta property="og:url" content="${escapeHtml(pageUrl)}" />
<meta property="og:type" content="website" />
<meta name="twitter:card" content="summary" />
${themeHeadScript()}
<link rel="stylesheet" href="/css/theme.css" />
<link rel="stylesheet" href="/css/components.css" />
${brandIcon ? `<link rel="icon" href="${escapeHtml(brandIcon)}" />` : ""}
</head>
<body>
${headerHtml(index)}

<main class="page">
  <div id="searchResults" class="search-results"></div>
  <div id="searchContent">
  <div class="app-hero">
    <div class="app-hero-top">
      ${iconOrFallbackHtml(app)}
      <div class="app-hero-titles">
        <div class="app-hero-name">${escapeHtml(app.name)}</div>
        <div class="app-hero-dev">${escapeHtml(developerName(app))}</div>
      </div>
    </div>
    <div class="app-hero-meta">
      <span class="app-trust-badge">${escapeHtml(trustLabel(app))}</span>
      <span class="app-trust-badge">${escapeHtml(displayVersion(app))}</span>
      ${app.ratingCount > 0 ? `<span class="app-trust-badge">${escapeHtml(displayRating(app))} ★</span>` : ""}
    </div>
    ${downloadUrl ? `<a class="app-download-large" href="${escapeHtml(downloadUrl)}">Download APK</a>` : ""}
  </div>

  ${screenshotsHtml ? `<div class="app-detail-section"><div class="app-screens">${screenshotsHtml}</div></div>` : ""}

  <div class="app-detail-section">
    <h2 class="app-section-title">About this app</h2>
    <div class="app-description">${renderMarkdown(app.description || summary)}</div>
  </div>
  </div>
  ${footerHtml()}
</main>

${themeScript()}
</body>
</html>`;
};
