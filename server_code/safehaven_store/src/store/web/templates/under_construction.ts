import { escapeHtml, brandIconUrl } from "../lib/shared.ts";
import { footerHtml } from "../components/footer.ts";
import { headerHtml, themeHeadScript, themeScript } from "../components/header.ts";

export const renderUnderConstruction = (index, wrongPassword) => {
  const brandIcon = brandIconUrl(index);
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SafeHaven Store</title>
<meta name="description" content="SafeHaven Store is coming soon." />
${themeHeadScript()}
<link rel="stylesheet" href="/css/theme.css" />
<link rel="stylesheet" href="/css/components.css" />
${brandIcon ? `<link rel="icon" href="${escapeHtml(brandIcon)}" />` : ""}
</head>
<body>
${headerHtml(index)}

<main class="page">
  <div class="construction-notice">
    <div class="construction-title">Under construction</div>
    <div class="construction-sub">SafeHaven Store is on its way. Check back soon.</div>
    <form class="unlock-form" method="POST" action="/unlock">
      <input type="password" name="password" placeholder="Access code" autocomplete="off" required />
      <button type="submit">Unlock</button>
    </form>
    ${wrongPassword ? `<div class="unlock-error">Incorrect access code</div>` : ""}
  </div>
  ${footerHtml()}
</main>

${themeScript()}
</body>
</html>`;
};
