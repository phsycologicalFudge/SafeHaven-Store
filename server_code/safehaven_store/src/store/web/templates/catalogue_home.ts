import { escapeHtml, iconOrFallbackHtml, displayRating } from "../lib/shared.ts";
import { topCharts, newArrivals, topInCategory, dailyShuffledCategoryKeys } from "../data/catalogue_ranking.ts";
import { footerHtml } from "../components/footer.ts";
import { headerHtml, themeHeadScript, themeScript } from "../components/header.ts";

const appTile = (app) => `
  <a class="app-tile" href="/app/${encodeURIComponent(app.packageName)}">
    ${iconOrFallbackHtml(app)}
    <div class="app-tile-name">${escapeHtml(app.name)}</div>
    ${app.ratingCount > 0 ? `<div class="app-tile-rating">${escapeHtml(displayRating(app))} ★</div>` : ""}
  </a>`;

const sectionChevron = `<svg class="section-chevron" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M9 6l6 6-6 6"></path></svg>`;

const horizontalSection = (title, apps, href) => {
  if (!apps.length) return "";
  const headerInner = `<span>${escapeHtml(title)}</span>${sectionChevron}`;
  const headerTag = href
    ? `<a class="section-header-link" href="${href}">${headerInner}</a>`
    : `<span class="section-header-link">${headerInner}</span>`;
  return `
  <div class="app-section">
    <h2 class="section-header">${headerTag}</h2>
    <div class="h-scroll">${apps.map(appTile).join("")}</div>
  </div>`;
};

export const renderCatalogueHome = (index, brandIcon) => {
  const apps = (index.apps || []).filter((a) => a.versions && a.versions.length > 0);
  const charts = topCharts(apps, 20);
  const arrivals = newArrivals(apps, 20);

  const categoryKeys = dailyShuffledCategoryKeys(index.categories || {});
  const catKeyA = categoryKeys[0];
  const catKeyB = categoryKeys[1];
  const catLabelA = catKeyA ? (index.categories[catKeyA] || catKeyA) : null;
  const catLabelB = catKeyB ? (index.categories[catKeyB] || catKeyB) : null;
  const topInA = catKeyA ? topInCategory(apps, catKeyA, 15) : [];
  const topInB = catKeyB ? topInCategory(apps, catKeyB, 15) : [];

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SafeHaven Store</title>
<meta name="description" content="An open source, privacy-first Android app store." />
<meta property="og:title" content="SafeHaven Store" />
<meta property="og:description" content="An open source, privacy-first Android app store." />
<meta property="og:type" content="website" />
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
    ${horizontalSection("Top charts", charts)}
    ${topInA.length ? horizontalSection(catLabelA, topInA, `/?cat=${encodeURIComponent(catKeyA)}`) : ""}
    ${topInB.length ? horizontalSection(catLabelB, topInB, `/?cat=${encodeURIComponent(catKeyB)}`) : ""}
    ${horizontalSection("New arrivals", arrivals)}
  </div>
  ${footerHtml()}
</main>

${themeScript()}
</body>
</html>`;
};
