const ALLOWED_TAGS = new Set([
  "p", "br", "b", "i", "em", "strong", "u", "s", "del",
  "h1", "h2", "h3", "h4", "h5", "h6",
  "ul", "ol", "li",
  "a", "code", "pre", "blockquote", "hr",
  "table", "thead", "tbody", "tr", "th", "td",
  "sub", "sup", "small",
]);

const BLOCK_TAGS = new Set([
  "p", "h1", "h2", "h3", "h4", "h5", "h6",
  "ul", "ol", "li", "pre", "blockquote", "hr",
  "table", "thead", "tbody", "tr", "th", "td",
]);

const ALLOWED_ATTRS = {
  a: new Set(["href"]),
};

const VOID_TAGS = new Set(["br", "hr"]);

const tagName = (tag) => {
  const match = tag.match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)/);
  return match ? match[1].toLowerCase() : "";
};

const stripTag = (tag) => {
  const name = tagName(tag);
  if (!name || !ALLOWED_TAGS.has(name)) return "";

  const isClosing = tag[1] === "/";
  if (isClosing) return `</${name}>`;

  const allowed = ALLOWED_ATTRS[name];
  let attrs = "";

  if (allowed) {
    const attrRegex = /([a-zA-Z-]+)\s*=\s*"([^"]*)"/g;
    let m;
    while ((m = attrRegex.exec(tag)) !== null) {
      const attrName = m[1].toLowerCase();
      if (attrName.startsWith("on")) continue;
      if (!allowed.has(attrName)) continue;
      let val = m[2];
      if (attrName === "href") {
        if (!/^https?:\/\//i.test(val) && !val.startsWith("/") && !val.startsWith("#")) continue;
        if (/^javascript:/i.test(val)) continue;
      }
      attrs += ` ${attrName}="${val}"`;
    }
  }

  if (name === "a") {
    attrs += ' target="_blank" rel="noopener noreferrer"';
  }

  if (VOID_TAGS.has(name)) return `<${name}${attrs} />`;
  return `<${name}${attrs}>`;
};

const sanitizeHtml = (raw) => {
  return raw.replace(/<[^>]+>/g, (tag) => stripTag(tag));
};

const isHtml = (text) => /<\/?[a-zA-Z][^>]*>/.test(text);

const inlineMarkdown = (text) => {
  let out = text
    .replace(/&(?!(?:[a-zA-Z][a-zA-Z0-9]*|#[0-9]+|#x[0-9a-fA-F]+);)/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

  out = out.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
  out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/__([^_]+)__/g, "<strong>$1</strong>");
  out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
  out = out.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>");
  out = out.replace(/(^|[^_])_([^_\n]+)_(?!_)/g, "$1<em>$2</em>");
  return out;
};

const renderPlainMarkdown = (text) => {
  const blocks = text.split(/\n\s*\n/);
  return blocks
    .map((block) => {
      const lines = block.split("\n").map((l) => l.trim()).filter(Boolean);
      if (!lines.length) return "";
      const isList = lines.every((l) => /^[*-]\s+/.test(l));
      if (isList) {
        return "<ul>" + lines.map((l) =>
          `<li>${inlineMarkdown(l.replace(/^[*-]\s+/, ""))}</li>`
        ).join("") + "</ul>";
      }
      return `<p>${lines.map(inlineMarkdown).join("<br>")}</p>`;
    })
    .join("");
};

const renderInlineHtmlMarkdown = (text) => {
  const tags = [];
  const protectedText = text.replace(/<[^>]+>/g, (tag) => {
    const token = `SAFEHAVENHTMLTAG${tags.length}PLACEHOLDER`;
    tags.push(stripTag(tag));
    return token;
  });

  let rendered = renderPlainMarkdown(protectedText);
  for (let i = 0; i < tags.length; i++) {
    rendered = rendered.replaceAll(`SAFEHAVENHTMLTAG${i}PLACEHOLDER`, tags[i]);
  }
  return rendered;
};

const renderBlockHtmlMarkdown = (text) => {
  let literalDepth = 0;
  return text.split(/(<[^>]+>)/g).map((part) => {
    if (!part) return "";
    if (part[0] !== "<") {
      return literalDepth > 0 ? part : inlineMarkdown(part);
    }

    const name = tagName(part);
    const safeTag = stripTag(part);
    if (!safeTag) return "";

    if ((name === "pre" || name === "code") && part[1] !== "/") literalDepth += 1;
    if ((name === "pre" || name === "code") && part[1] === "/") literalDepth = Math.max(0, literalDepth - 1);
    return safeTag;
  }).join("");
};

export const renderMarkdown = (raw) => {
  const text = (raw || "").toString().trim();
  if (!text) return "";

  if (isHtml(text)) {
    const tags = text.match(/<[^>]+>/g) || [];
    const hasBlockHtml = tags.some((tag) => BLOCK_TAGS.has(tagName(tag)));
    return hasBlockHtml ? renderBlockHtmlMarkdown(text) : renderInlineHtmlMarkdown(text);
  }

  return renderPlainMarkdown(text);
};
