type FooterLink = { label: string; url: string; external?: boolean };
type FooterColumn = { heading: string; links: FooterLink[] };

export const COMPANY_LINE = "ColourSwift Ltd &middot; Registered in England and Wales";

export const FOOTER_COLUMNS: FooterColumn[] = [
  {
    heading: "Links",
    links: [
      { label: "Account", url: "https://account.colourswift.com/account", external: true },
      { label: "AvarionX Antivirus", url: "https://play.google.com/store/apps/details?id=com.colourswift.cssecurity", external: true },
      { label: "AvarionX VPN", url: "https://play.google.com/store/apps/details?id=com.colourswift.avarionxvpn", external: true },
      { label: "SafeHaven Store", url: "https://github.com/phsycologicalFudge/SafeHaven-Store", external: true },
      { label: "VTTI Cloud", url: "https://platform.colourswift.com/", external: true },
    ],
  },
  {
    heading: "Help",
    links: [
      { label: "Contact us", url: "mailto:support@colourswift.com" },
      { label: "AvarionX documentation", url: "https://colourswift.com/docs" },
      { label: "SafeHaven documentation", url: "https://colourswift.com/safehaven/" },
      { label: "Status", url: "https://api.colourswift.com/health" },
    ],
  },
  {
    heading: "About ColourSwift",
    links: [
      { label: "About us", url: "https://colourswift.com/about" },
      { label: "ColourSwift Ltd", url: "https://find-and-update.company-information.service.gov.uk/company/16744785", external: true },
    ],
  },
  {
    heading: "Legal",
    links: [
      { label: "Privacy policy", url: "https://colourswift.com/Policies/Private-Policy" },
      { label: "Terms of use", url: "https://colourswift.com/Policies/Terms-Of-Use" },
      { label: "Refund policy", url: "https://colourswift.com/Policies/Refund-Policy" },
    ],
  },
];

const linkHtml = (l: FooterLink) =>
  `<li><a href="${l.url}"${l.external ? ' target="_blank" rel="noopener"' : ""}>${l.label}</a></li>`;

const columnHtml = (c: FooterColumn) =>
  `<div class="cs-footer__column">
        <h2 class="cs-footer__heading">${c.heading}</h2>
        <ul class="cs-footer__links" role="list">${c.links.map(linkHtml).join("")}</ul>
      </div>`;

export const footerHtml = () => {
  const year = new Date().getUTCFullYear();

  return `
  <footer class="cs-footer">
    <div class="cs-footer__inner">
      <div class="cs-footer__columns">
      ${FOOTER_COLUMNS.map(columnHtml).join("")}
      </div>
      <div class="cs-footer__bottom">
        <span>&copy; ${year} ${COMPANY_LINE}</span>
      </div>
    </div>
  </footer>`;
};