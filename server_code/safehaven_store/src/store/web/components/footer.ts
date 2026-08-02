export const OPERATOR_NAME = "ColourSwift Technologies";

export const LEGAL_LINKS = [
  { label: "Status", url: "https://api.colourswift.com/health" },
  { label: "Privacy", url: "https://colourswift.com/Policies/Private-Policy" },
  { label: "Terms", url: "https://colourswift.com/Policies/Terms-Of-Use" },
];

export const COMMUNITY_LINKS_ENABLED = true;

export const COMMUNITY_LINKS = [
  { label: "GitHub", url: "https://github.com/phsycologicalFudge/SafeHaven-Store" },
  { label: "Discord", url: "https://discord.gg/VYubQJfcYM" },
];

export const footerHtml = () => {
  const year = new Date().getUTCFullYear();

  const legalLine = LEGAL_LINKS
    .map((l) => `<a href="${l.url}">${l.label}</a>`)
    .join(" <span>|</span> ");

  const communityLine = COMMUNITY_LINKS_ENABLED && COMMUNITY_LINKS.length
    ? COMMUNITY_LINKS
        .map((l) => `<a href="${l.url}" target="_blank" rel="noopener noreferrer">${l.label}</a>`)
        .join(" <span>|</span> ")
    : "";

  return `
  <footer>
    <div class="footer-inner">
      <div>&copy; ${year} ${OPERATOR_NAME}</div>
      <div>${legalLine}</div>
    </div>
    ${communityLine ? `<div class="footer-community">${communityLine}</div>` : ""}
  </footer>`;
};
