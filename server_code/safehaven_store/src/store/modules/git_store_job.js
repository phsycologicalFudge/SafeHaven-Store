import { createSubmission, advanceSubmissionToScan, setAppImages, getStoreAppById, getStoreAppByPackage } from "../store_db.js";
import { addOrUpdateApp } from "../storage.js";
import { uploadImageFromUrl } from "./images/image_upload.js";
import { nowUnix, cryptoRandomHex, normalizeStoreText, parseScreenshots, buildIndexAppEntry, COMMUNITY_DEVELOPER_ID } from "../helpers/store_helpers.js";
import { githubHeaders, normalizeGitHubRepoUrl, parseGitHubRepo, repoUrlVariants, githubLatestRelease, normalizeAssetText, apkAssetsOf, scoreApkAsset, findApkAsset, tagToVersionCode, uploadBufferToStaging } from "../helpers/github_helpers.js";

const IMPORT_LIMIT           = 50;
const MAX_APK_BYTES          = 100 * 1024 * 1024;
const ADMIN_MAX_APK_BYTES    = 200 * 1024 * 1024;
const MAX_ICON_BYTES         = 4 * 1024 * 1024;
const MAX_SCREENSHOT_BYTES   = 4 * 1024 * 1024;

const githubSearch = async (env, query, perPage = 50) => {
  const url = `https://api.github.com/search/repositories?q=${encodeURIComponent(query)}&sort=stars&order=desc&per_page=${perPage}`;
  const res = await fetch(url, { headers: githubHeaders(env) });
  if (!res.ok) throw new Error(`github_search_failed:${res.status}`);

  const data = await res.json();

  return (data.items || [])
    .filter((item) => item?.full_name && item?.html_url)
    .map((item) => ({
      fullName:    item.full_name,
      name:        item.name || item.full_name.split("/").pop(),
      description: item.description || "",
      stars:       item.stargazers_count || 0,
      topics:      Array.isArray(item.topics) ? item.topics : [],
      repoUrl:     normalizeGitHubRepoUrl(item.html_url) || `https://github.com/${item.full_name}`,
      iconUrl:     null,
    }));
};

const githubRepoDetails = async (env, owner, repo) => {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}`,
    { headers: githubHeaders(env) }
  );

  if (!res.ok) return null;

  const data = await res.json();

  return {
    fullName:    data.full_name || `${owner}/${repo}`,
    name:        data.name || repo,
    description: data.description || "",
    stars:       data.stargazers_count || 0,
    topics:      Array.isArray(data.topics) ? data.topics : [],
    repoUrl:     normalizeGitHubRepoUrl(data.html_url) || `https://github.com/${owner}/${repo}`,
    iconUrl:     null,
  };
};


const decodeBase64Utf8 = (value) => {
  try {
    const binary = atob((value || "").replace(/\s/g, ""));
    const bytes  = new Uint8Array(binary.length);

    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }

    return new TextDecoder().decode(bytes);
  } catch {
    return "";
  }
};

const stripReadmeToDescription = (readme) => {
  let text = (readme || "")
    .toString()
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n");

  text = text
    .replace(/```[\s\S]*?```/g, "\n\n")
    .replace(/<picture\b[\s\S]*?<\/picture>/gi, "\n\n")
    .replace(/<svg\b[\s\S]*?<\/svg>/gi, "\n\n")
    .replace(/<table\b[\s\S]*?<\/table>/gi, "\n\n")
    .replace(/<\!--[\s\S]*?-->/g, "\n\n")
    .replace(/^\s*\[!\[[^\]]*\]\([^)]*\)\]\([^)]*\)\s*$/gm, "\n")
    .replace(/^\s*!\[[^\]]*\]\([^)]*\)\s*$/gm, "\n")
    .replace(/^\s*\[<img\b[\s\S]*?>\]\([^)]*\)\s*$/gim, "\n")
    .replace(/^\s*<a\b[^>]*>\s*<img\b[\s\S]*?<\/a>\s*$/gim, "\n")
    .replace(/^\s*<img\b[^>]*>\s*$/gim, "\n")
    .replace(/<p\b[^>]*align=["']center["'][^>]*>[\s\S]*?<\/p>/gi, (block) => {
      const withoutImgs = block
        .replace(/<img\b[^>]*>/gi, "")
        .replace(/<a\b[^>]*href=["']#[^"']+["'][^>]*>[\s\S]*?<\/a>/gi, "");

      const plain = withoutImgs.replace(/<[^>]+>/g, "").trim();

      if (!plain) return "\n\n";
      if (plain.includes("•") || plain.includes("&bull;")) return "\n\n";
      if (plain.length > 180) return "\n\n";

      return `\n\n${plain}\n\n`;
    })
    .replace(/<h[1-6]\b[^>]*>/gi, "\n\n")
    .replace(/<\/h[1-6]>/gi, "\n\n")
    .replace(/<p\b[^>]*>/gi, "\n\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<div\b[^>]*>/gi, "\n\n")
    .replace(/<\/div>/gi, "\n\n")
    .replace(/<section\b[^>]*>/gi, "\n\n")
    .replace(/<\/section>/gi, "\n\n")
    .replace(/<hr\s*\/?>/gi, "\n\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<ul\b[^>]*>/gi, "\n")
    .replace(/<\/ul>/gi, "\n")
    .replace(/<ol\b[^>]*>/gi, "\n")
    .replace(/<\/ol>/gi, "\n")
    .replace(/<li\b[^>]*>/gi, "- ")
    .replace(/<\/li>/gi, "\n")
    .replace(/^\s*#{1,6}\s+(.+?)\s*#*\s*$/gm, "\n\n$1\n\n")
    .replace(/^\s*>\s*\[!(?:note|tip|important|warning|caution)\]\s*$/gim, "\n")
    .replace(/^\s*>\s?/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "- ")
    .replace(/^\s*\d+\.\s+/gm, (match) => match.trim() + " ")
    .replace(/\[([^\]]*)\]\(([^)]*)\)/g, (full, label, url) => {
      const cleanLabel = (label || "").trim();
      const cleanUrl = (url || "").trim();

      if (!cleanLabel && cleanUrl) return cleanUrl;
      if (!cleanLabel) return "";
      return cleanLabel;
    })
    .replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, "`$1`")
    .replace(/<b\b[^>]*>([\s\S]*?)<\/b>/gi, "**$1**")
    .replace(/<strong\b[^>]*>([\s\S]*?)<\/strong>/gi, "**$1**")
    .replace(/<i\b[^>]*>([\s\S]*?)<\/i>/gi, "$1")
    .replace(/<em\b[^>]*>([\s\S]*?)<\/em>/gi, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&bull;/gi, "•")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/gi, "\"")
    .replace(/\*\*([^*\n]+)\*\*/g, "$1")
    .replace(/__([^_\n]+)__/g, "$1")
    .replace(/\*([^*\n]+)\*/g, "$1")
    .replace(/_([^_\n]+)_/g, "$1")
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  if (!text) return null;

  return text.slice(0, 4000).trim();
};

const githubReadmeRaw = async (env, owner, repo) => {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/readme`,
    { headers: githubHeaders(env) }
  );

  if (!res.ok) return null;

  const data = await res.json();
  const raw  = decodeBase64Utf8(data.content || "");

  return raw || null;
};

const githubReadmeDescription = async (env, owner, repo) => {
  const raw = await githubReadmeRaw(env, owner, repo);
  if (!raw) return null;

  return stripReadmeToDescription(raw);
};

const htmlAttrValue = (tag, attr) => {
  const re = new RegExp(`${attr}\\s*=\\s*["']([^"']+)["']`, "i");
  return (tag.match(re) || [])[1] || "";
};

const isLikelyScreenshotImage = (label, src) => {
  const cleanSrc = (src || "").toString();
  const text = `${label || ""} ${cleanSrc}`.toLowerCase();

  if (!/\.(png|jpe?g|webp)(?:[?#].*)?$/i.test(cleanSrc)) return false;

  const hardRejectTerms = [
    "shields.io",
    "badgen.net",
    "coveralls",
    "codecov",
    "badge",
    "license",
    "version",
    "stars",
    "downloads",
    "workflow",
    "build",
    "ci",
    "status",
  ];

  if (hardRejectTerms.some((term) => text.includes(term))) return false;

  let score = 0;

  const strongTerms = [
    "screenshot",
    "screenshots",
    "phone_screenshots",
    "phonescreenshots",
    "phone-screenshots",
    "preview",
    "demo",
    "showcase",
    "mockup",
    "screen",
    "screens",
    "fastlane",
    "metadata/android",
    "play/listings",
    "store-listing",
    "store_listing",
  ];

  const weakTerms = [
    "image",
    "images",
    "img",
    "gallery",
    "media",
    "assets",
    "docs",
    "readme",
  ];

  const rejectTerms = [
    "logo",
    "icon",
    "avatar",
    "banner",
    "header",
    "brand",
    "qr",
    "donate",
    "sponsor",
  ];

  for (const term of strongTerms) {
    if (text.includes(term)) score += 4;
  }

  for (const term of weakTerms) {
    if (text.includes(term)) score += 1;
  }

  for (const term of rejectTerms) {
    if (text.includes(term)) score -= 4;
  }

  if (/\/(?:screenshots?|previews?|demo|showcase|gallery)\//i.test(cleanSrc)) score += 5;
  if (/\/fastlane\/metadata\/android\//i.test(cleanSrc)) score += 5;
  if (/\/images\/(?:phoneScreenshots|sevenInchScreenshots|tenInchScreenshots)\//i.test(cleanSrc)) score += 5;
  if (/(?:^|\/)(?:image|img|screenshot|screen)[-_]?\d*\.(?:png|jpe?g|webp)(?:[?#].*)?$/i.test(cleanSrc)) score += 2;

  return score >= 4;
};

const normalizeReadmeImageUrl = (owner, repo, src) => {
  const clean = (src || "").toString().trim();

  if (!clean) return null;
  if (clean.startsWith("#")) return null;
  if (clean.startsWith("data:")) return null;
  if (clean.startsWith("mailto:")) return null;

  const noQuery = clean.split("#")[0];

  if (/^https?:\/\//i.test(noQuery)) {
    const blob = noQuery.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/blob\/([^/]+)\/(.+)$/i);
    if (blob) {
      return `https://raw.githubusercontent.com/${blob[1]}/${blob[2]}/${blob[3]}/${blob[4].split("?")[0]}`;
    }

    const rawBlob = noQuery.match(/^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/(.+)$/i);
    if (rawBlob) return noQuery;

    const userAsset = noQuery.match(/^https:\/\/github\.com\/user-attachments\/assets\/[^?#]+/i);
    if (userAsset) return noQuery;

    return noQuery;
  }

  const withoutPrefix = noQuery
    .replace(/^\.\//, "")
    .replace(/^\/+/, "")
    .split("?")[0];

  if (!withoutPrefix) return null;

  return `https://raw.githubusercontent.com/${owner}/${repo}/HEAD/${withoutPrefix}`;
};

const readmeScreenshotUrls = (owner, repo, rawReadme) => {
  const readme = rawReadme || "";
  const found = [];

  const add = (label, src) => {
    const url = normalizeReadmeImageUrl(owner, repo, src);
    if (!url) return;
    if (!isLikelyScreenshotImage(label, url)) return;
    if (found.some((item) => item.url === url)) return;

    found.push({ label, url });
  };

  for (const match of readme.matchAll(/!\[([^\]]*)]\(([^)\n]+?)(?:\s+["'][^"']*["'])?\)/g)) {
    add(match[1] || "", match[2] || "");
  }

  for (const match of readme.matchAll(/<img\b[^>]*>/gi)) {
    const tag = match[0] || "";
    const src = htmlAttrValue(tag, "src");
    const label = [
      htmlAttrValue(tag, "alt"),
      htmlAttrValue(tag, "title"),
      htmlAttrValue(tag, "class"),
      htmlAttrValue(tag, "id"),
    ].filter(Boolean).join(" ");

    add(label, src);
  }

  for (const match of readme.matchAll(/src=["']([^"']+\.(?:png|jpe?g|webp)(?:[?#][^"']*)?)["']/gi)) {
    add("", match[1] || "");
  }

  return found.slice(0, 6);
};

const uploadReadmeScreenshot = (env, packageName, slot, imageUrl) =>
  uploadImageFromUrl(env, packageName, slot, imageUrl, MAX_SCREENSHOT_BYTES);

const saveReadmeScreenshotsIfMissing = async (env, app, owner, repo, rawReadme) => {
  if (!app) return [];
  if (app.developer_id !== COMMUNITY_DEVELOPER_ID) return [];
  if (Number(app.auto_tracked || 0) !== 1) return [];
  if (Number(app.claimed || 0) === 1) return [];

  const existingScreenshots = parseScreenshots(app.screenshots_json);
  if (existingScreenshots.length > 0) return existingScreenshots;

  const candidates = readmeScreenshotUrls(owner, repo, rawReadme);
  if (!candidates.length) return [];

  const screenshotKeys = [];

  for (let i = 0; i < candidates.length && screenshotKeys.length < 6; i++) {
    const slot = `screenshot_${screenshotKeys.length + 1}`;
    const key = await uploadReadmeScreenshot(env, app.package_name, slot, candidates[i].url);

    if (key) {
      screenshotKeys.push(key);
    }
  }

  if (!screenshotKeys.length) return [];

  await setAppImages(env, app.id, {
    iconKey: app.icon_key || null,
    screenshotKeys,
  });

  return screenshotKeys;
};

export const refreshGitHubMetadataForApp = async (env, app, owner, repo) => {
  let details = null;
  let rawReadme = null;
  let readmeDescription = null;

  try {
    details = await githubRepoDetails(env, owner, repo);
  } catch {
    details = null;
  }

  try {
    rawReadme = await githubReadmeRaw(env, owner, repo);
    readmeDescription = rawReadme ? stripReadmeToDescription(rawReadme) : null;
  } catch {
    rawReadme = null;
    readmeDescription = null;
  }

  if (!details && !readmeDescription) return false;

  const summary = normalizeStoreText((details?.description || app.summary || "").slice(0, 200).trim()) || null;
  const description = normalizeStoreText(readmeDescription || details?.description || app.description || null);

  const category = inferCategory(
    {
      fullName: details?.fullName || `${owner}/${repo}`,
      name: details?.name || app.name,
      description: details?.description || summary || "",
      topics: details?.topics || [],
    },
    readmeDescription || ""
  );

  await env.api_control_db
    .prepare(
      `UPDATE store_apps
       SET summary = ?2,
           description = ?3,
           category = ?4,
           updated_at = ?5
       WHERE id = ?1
         AND auto_tracked = 1
         AND claimed = 0`
    )
    .bind(
      app.id,
      summary,
      description,
      category,
      nowUnix()
    )
    .run();

  let updatedApp = await getStoreAppById(env, app.id);

  if (updatedApp && rawReadme) {
    await saveReadmeScreenshotsIfMissing(env, updatedApp, owner, repo, rawReadme);
    updatedApp = await getStoreAppById(env, app.id);
  }

  if (updatedApp) {
    await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
  }

  return true;
};

const parseOpenHubXml = (xml) => {
  const results       = [];
  const projectBlocks = xml.match(/<project\b[^>]*>[\s\S]*?<\/project>/g) || [];

  for (const block of projectBlocks) {
    const name        = (block.match(/<name>([\s\S]*?)<\/name>/)               || [])[1]?.trim() || "";
    const description = (block.match(/<description>([\s\S]*?)<\/description>/) || [])[1]?.trim() || "";

    const urlTags = block.match(/<url>(https?:\/\/github\.com\/[^<]+)<\/url>/g) || [];

    for (const tag of urlTags) {
      const raw     = (tag.match(/<url>([\s\S]*?)<\/url>/) || [])[1]?.trim() || "";
      const repoUrl = normalizeGitHubRepoUrl(raw);

      if (!repoUrl) continue;

      const m = repoUrl.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)$/i);
      if (!m) continue;

      results.push({
        fullName:    `${m[1]}/${m[2]}`,
        name:        name || m[2],
        description: description.replace(/<[^>]+>/g, ""),
        stars:       0,
        repoUrl,
        iconUrl:     null,
      });

      break;
    }
  }

  return results;
};

const openHubSearch = async (env, query, page = 1) => {
  const apiKey = (env.OPENHUB_API_KEY || "").trim();
  if (!apiKey) return [];

  const url = `https://www.openhub.net/projects.xml?query=${encodeURIComponent(query)}&sort=rating&page=${page}&api_key=${apiKey}`;
  const res = await fetch(url, { headers: { "user-agent": "SafeHaven-Store/1.0" } });
  if (!res.ok) throw new Error(`openhub_search_failed:${res.status}`);

  const xml = await res.text();
  return parseOpenHubXml(xml);
};


const assetNameToVersionName = (assetName) => {
  const name = (assetName || "").toString().trim();

  const versionMatch = name.match(/(?:^|[-_])v(\d+(?:[._]\d+){1,5}(?:[+._-][a-z0-9.]+)?)(?=\.apk$|[-_])/i);
  if (!versionMatch) return null;

  return `v${versionMatch[1].replace(/_/g, ".")}`;
};

const versionNameToVersionCode = (versionName) => {
  const clean = (versionName || "")
    .toString()
    .trim()
    .replace(/^v/i, "");

  const parts = clean.match(/\d+/g);
  if (!parts || !parts.length) return null;

  const major = Number(parts[0] || 0);
  const minor = Number(parts[1] || 0);
  const patch = Number(parts[2] || 0);
  const build = Number(parts[3] || 0);

  if (
    !Number.isSafeInteger(major) ||
    !Number.isSafeInteger(minor) ||
    !Number.isSafeInteger(patch) ||
    !Number.isSafeInteger(build)
  ) {
    return null;
  }

  if (major < 0 || minor < 0 || patch < 0 || build < 0) return null;
  if (major > 9999 || minor > 999 || patch > 999 || build > 99) return null;

  return major * 100000000 + minor * 100000 + patch * 100 + build;
};

const CATEGORY_RULES = [
  {
    category: "security",
    weight: 5,
    terms: [
      "security", "privacy", "vpn", "proxy", "wireguard", "v2ray", "shadowsocks", "tor",
      "firewall", "dns", "adblock", "blocklist", "malware", "antivirus", "authenticator",
      "2fa", "totp", "password", "keepass", "vault", "encryption", "encrypted",
      "crypto", "cryptography", "keychain", "root", "magisk", "kernelsu", "apatch",
      "lsposed", "permission", "permissions", "tracker", "tracking", "secure"
    ],
  },
  {
    category: "communication",
    weight: 5,
    terms: [
      "communication", "chat", "messaging", "message", "sms", "mms", "email", "mail",
      "mastodon", "matrix", "xmpp", "telegram", "signal", "fediverse", "social",
      "client", "push", "notification", "notifications", "gotify", "ntfy", "forum",
      "lemmy", "reddit", "discord", "irc", "contacts", "dialer", "phone"
    ],
  },
  {
    category: "entertainment",
    weight: 4,
    terms: [
      "entertainment", "music", "audio", "video", "player", "media", "youtube",
      "stream", "streaming", "anime", "manga", "novel", "reader", "book", "books",
      "comic", "comics", "movie", "movies", "tv", "podcast", "radio", "game",
      "games", "emulator", "retro", "lyrics", "song", "songs", "gallery", "photo",
      "photos", "image", "images", "pixiv"
    ],
  },
  {
    category: "productivity",
    weight: 4,
    terms: [
      "productivity", "todo", "task", "tasks", "notes", "note", "notepad", "calendar",
      "planner", "schedule", "habit", "habits", "reminder", "reminders", "focus",
      "timer", "pomodoro", "journal", "diary", "memos", "documents", "document",
      "office", "markdown", "backup", "sync", "clipboard", "ocr", "scan", "scanner"
    ],
  },
  {
    category: "utilities",
    weight: 4,
    terms: [
      "utility", "utilities", "tool", "tools", "file", "files", "filemanager",
      "file-manager", "manager", "calculator", "calc", "keyboard", "launcher",
      "wallpaper", "weather", "clock", "alarm", "compass", "flashlight", "brightness",
      "volume", "wifi", "bluetooth", "adb", "logcat", "terminal", "shell", "termux",
      "widget", "widgets", "cleaner", "storage", "download", "downloader", "clipboard"
    ],
  },
  {
    category: "finance",
    weight: 5,
    terms: [
      "finance", "budget", "budgeting", "expense", "expenses", "money", "bank",
      "banking", "wallet", "crypto-wallet", "invoice", "accounting", "stocks",
      "portfolio", "payments", "payment"
    ],
  },
  {
    category: "health",
    weight: 5,
    terms: [
      "health", "fitness", "workout", "exercise", "medical", "medicine", "medication",
      "period", "sleep", "calorie", "calories", "nutrition", "wellness", "step",
      "steps", "running", "training"
    ],
  },
  {
    category: "education",
    weight: 5,
    terms: [
      "education", "learn", "learning", "study", "school", "university", "language",
      "dictionary", "translator", "flashcard", "flashcards", "anki", "kanji",
      "math", "calculator", "science", "quiz", "reader", "books", "library"
    ],
  },
];

const normaliseCategoryText = (parts) =>
  parts
    .filter(Boolean)
    .join(" ")
    .toLowerCase()
    .replace(/[^a-z0-9+#._-]+/g, " ");

const inferCategory = (candidate, readmeDescription = "") => {
  const topics = Array.isArray(candidate.topics) ? candidate.topics : [];

  const text = normaliseCategoryText([
    candidate.fullName,
    candidate.name,
    candidate.description,
    topics.join(" "),
    readmeDescription,
  ]);

  const padded = ` ${text} `;
  const scores = new Map();

  for (const rule of CATEGORY_RULES) {
    let score = 0;

    for (const term of rule.terms) {
      const clean = term.toLowerCase();
      const topicHit = topics.some((t) => t.toLowerCase() === clean);
      const textHit = padded.includes(` ${clean} `) || padded.includes(clean.replace(/-/g, " "));

      if (topicHit) score += rule.weight + 3;
      else if (textHit) score += rule.weight;
    }

    if (score > 0) {
      scores.set(rule.category, (scores.get(rule.category) || 0) + score);
    }
  }

  const ranked = [...scores.entries()].sort((a, b) => b[1] - a[1]);
  return ranked[0]?.[0] || "other";
};

const getAppByRepoUrl = async (env, repoUrl) => {
  const variants = repoUrlVariants(repoUrl);
  if (!variants.length) return null;

  const row = await env.api_control_db
    .prepare(
      `SELECT *
       FROM store_apps
       WHERE repo_url = ?1 OR repo_url = ?2 OR repo_url = ?3
       LIMIT 1`
    )
    .bind(variants[0], variants[1], variants[2])
    .first();

  return row || null;
};

const getAutoTrackedAppsForReadmeSweep = async (env, limit = 50) => {
  const rows = await env.api_control_db
    .prepare(
      `SELECT *
       FROM store_apps
       WHERE auto_tracked = 1
         AND status = 'active'
         AND repo_url LIKE 'https://github.com/%'
       ORDER BY updated_at ASC
       LIMIT ?1`
    )
    .bind(limit)
    .all();

  return rows.results || [];
};

const updateAutoTrackedAppDescription = async (env, appId, summary, description, category) => {
  await env.api_control_db
    .prepare(
      `UPDATE store_apps
       SET summary = ?2,
           description = ?3,
           category = ?4,
           updated_at = ?5
       WHERE id = ?1
         AND auto_tracked = 1
         AND claimed = 0`
    )
    .bind(
      (appId || "").toString().trim(),
      summary || null,
      description || null,
      category || "other",
      nowUnix()
    )
    .run();
};


const deleteAppById = async (env, appId) => {
  const id = (appId || "").toString().trim();
  if (!id) return;

  await env.api_control_db
    .prepare("DELETE FROM store_submissions WHERE app_id = ?1")
    .bind(id)
    .run();

  await env.api_control_db
    .prepare("DELETE FROM store_apps WHERE id = ?1 AND developer_id = ?2 AND claimed = 0")
    .bind(id, COMMUNITY_DEVELOPER_ID)
    .run();
};

const makePlaceholderPackageName = (fullName) => {
  const [ownerRaw, repoRaw] = (fullName || "").split("/");
  const norm = (s) => {
    const cleaned = (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    return cleaned || "x";
  };

  return `pending.github.${norm(ownerRaw)}.${norm(repoRaw)}`;
};

const displayNameOf = (candidate) =>
  (candidate.name || candidate.fullName.split("/").pop() || "Unknown App")
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();


const uploadIconFromUrl = (env, packageName, iconUrl) =>
  iconUrl ? uploadImageFromUrl(env, packageName, "icon", iconUrl, MAX_ICON_BYTES) : Promise.resolve(null);

const createUnclaimedStoreApp = async (env, { packageName, name, summary, description, repoUrl, iconKey, category }) => {
  const now = nowUnix();

  const existing = await env.api_control_db
    .prepare("SELECT id FROM store_apps WHERE package_name = ?1 LIMIT 1")
    .bind(packageName)
    .first();

  if (existing) return existing.id;

  const id = cryptoRandomHex(16);

  await env.api_control_db
    .prepare(
      `INSERT INTO store_apps
        (id, developer_id, package_name, name, summary, description,
         repo_url, repo_token, repo_verified, trust_level, status,
         claimed, auto_tracked, icon_key, category, created_at, updated_at, upstream)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, '', 0, 'unverified', 'active', 0, 1, ?8, ?9, ?10, ?10, NULL)`
    )
    .bind(
      id,
      COMMUNITY_DEVELOPER_ID,
      packageName,
      name,
      summary || null,
      description || null,
      repoUrl,
      iconKey || null,
      category || "other",
      now
    )
    .run();

  return id;
};

const hydrateCandidate = async (env, candidate) => {
  const [owner, repo] = candidate.fullName.split("/");

  if (candidate.iconUrl && candidate.description && candidate.stars) {
    return candidate;
  }

  const details = await githubRepoDetails(env, owner, repo);
  if (!details) return candidate;

  return {
    ...candidate,
    name:        candidate.name || details.name,
    description: candidate.description || details.description,
    stars:       candidate.stars || details.stars,
    topics:      candidate.topics?.length ? candidate.topics : details.topics,
    repoUrl:     candidate.repoUrl || details.repoUrl,
    iconUrl:     candidate.iconUrl || details.iconUrl,
  };
};

const importCandidate = async (env, rawCandidate) => {
  const candidate = await hydrateCandidate(env, rawCandidate);
  const repoUrl   = normalizeGitHubRepoUrl(candidate.repoUrl);

  if (!repoUrl) return { skipped: true, reason: "invalid_repo_url" };

  const byRepo = await getAppByRepoUrl(env, repoUrl);

  if (byRepo) {
    if (byRepo.upstream === "fdroid") {
      return { skipped: true, reason: "upstream_is_fdroid" };
    }

    const status      = (byRepo.status || "").toString().trim();
    const developerId = (byRepo.developer_id || "").toString().trim();
    const autoTracked = Number(byRepo.auto_tracked || 0) === 1;
    const claimed     = Number(byRepo.claimed || 0) === 1;

    if (status === "removed" && developerId === COMMUNITY_DEVELOPER_ID && autoTracked && !claimed) {
      await deleteAppById(env, byRepo.id);
    } else {
      return { skipped: true, reason: "already_tracked" };
    }
  }

  const [owner, repo] = candidate.fullName.split("/");
  if (!owner || !repo) return { skipped: true, reason: "invalid_full_name" };

  let release;
  try {
    release = await githubLatestRelease(env, owner, repo);
  } catch {
    return { skipped: true, reason: "no_stable_release" };
  }
  if (!release) return { skipped: true, reason: "no_stable_release" };

  const asset = findApkAsset(release, {
    assetMatch: rawCandidate.assetMatch,
    preferredAbi: rawCandidate.preferredAbi || "arm64-v8a",
  });

  if (!asset) return { skipped: true, reason: "no_matching_apk_asset" };

  const maxApkBytes = rawCandidate.adminImport === true
    ? ADMIN_MAX_APK_BYTES
    : MAX_APK_BYTES;

  if (asset.size > maxApkBytes) {
    return {
      skipped: true,
      reason: "apk_too_large",
      assetSize: asset.size,
      maxApkBytes,
      adminImport: rawCandidate.adminImport === true,
    };
  }

  const assetVersionName = assetNameToVersionName(asset.name);
  const versionName = tagToVersionCode(release.tag_name)
    ? release.tag_name
    : assetVersionName;

  const versionCode = tagToVersionCode(release.tag_name) || versionNameToVersionCode(assetVersionName);

  if (!versionName || !versionCode) {
    return {
      skipped: true,
      reason: "unparseable_version",
      releaseTag: release.tag_name,
      assetName: asset.name,
    };
  }

  const packageName = makePlaceholderPackageName(candidate.fullName);
  const byPkg       = await getStoreAppByPackage(env, packageName);
  if (byPkg) return { skipped: true, reason: "placeholder_collision" };

  let rawReadme = null;
  let readmeDescription = null;

  try {
    rawReadme = await githubReadmeRaw(env, owner, repo);
    readmeDescription = rawReadme ? stripReadmeToDescription(rawReadme) : null;
  } catch {
    rawReadme = null;
    readmeDescription = null;
  }

  const summary     = normalizeStoreText((candidate.description || "").slice(0, 200).trim()) || null;
  const description = normalizeStoreText(readmeDescription || candidate.description || null);
  const iconKey     = null;
  const category    = inferCategory(candidate, readmeDescription || "");

  const appId = await createUnclaimedStoreApp(env, {
    packageName,
    name: displayNameOf(candidate),
    summary,
    description,
    repoUrl,
    iconKey,
    category,
  });

  if (!appId) return { skipped: true, reason: "app_create_failed" };
  let screenshotKeys = [];

  if (rawReadme) {
    const createdApp = await getStoreAppById(env, appId);
    screenshotKeys = await saveReadmeScreenshotsIfMissing(env, createdApp, owner, repo, rawReadme);
  }

  let apkBuffer;

  try {
    const apkRes = await fetch(asset.browser_download_url, {
      headers: { "user-agent": "SafeHaven-Store/1.0" },
    });

    if (!apkRes.ok) {
      await deleteAppById(env, appId);
      return { skipped: true, reason: `apk_download_failed:${apkRes.status}` };
    }

    apkBuffer = await apkRes.arrayBuffer();
  } catch (e) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: `apk_download_error:${String(e?.message || e)}` };
  }

  if (apkBuffer.byteLength > maxApkBytes) {
    await deleteAppById(env, appId);
    return {
      skipped: true,
      reason: "apk_too_large_post_download",
      assetSize: apkBuffer.byteLength,
      maxApkBytes,
      adminImport: rawCandidate.adminImport === true,
    };
  }

  try {
    await uploadBufferToStaging(env, packageName, versionCode, apkBuffer);
  } catch (e) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: `staging_failed:${String(e?.message || e)}`, appId };
  }

  const submissionId = await createSubmission(env, {
    appId,
    developerId: COMMUNITY_DEVELOPER_ID,
    packageName,
    versionName,
    versionCode,
    stagingKey:  `staging/${packageName}/${versionCode}/app.apk`,
  });

  if (!submissionId) {
    await deleteAppById(env, appId);
    return { skipped: true, reason: "submission_create_failed", appId };
  }

  await advanceSubmissionToScan(env, submissionId);

  return {
    imported: true,
    appId,
    submissionId,
    packageName,
    versionCode,
    category,
    assetName: asset.name,
    hasIcon: !!iconKey,
    hasScreenshots: screenshotKeys.length > 0,
    hasReadmeDescription: !!readmeDescription,
  };
};

const collectCandidates = async (env) => {
  const seen       = new Set();
  const candidates = [];

  const add = (items) => {
    for (const item of items) {
      const repoUrl = normalizeGitHubRepoUrl(item.repoUrl);
      if (!repoUrl || !item.fullName) continue;

      const key = item.fullName.toLowerCase();

      if (!seen.has(key)) {
        seen.add(key);
        candidates.push({ ...item, repoUrl });
      }
    }
  };

  const GITHUB_QUERIES = [
    "topic:android language:kotlin",
    "topic:fdroid language:kotlin",
    "topic:android-app language:kotlin",
    "topic:android language:java",
  ];

  const OPENHUB_QUERIES = [
    "android mobile",
    "android app",
  ];

  for (const query of GITHUB_QUERIES) {
    if (candidates.length >= IMPORT_LIMIT * 4) break;

    try {
      add(await githubSearch(env, query, 50));
    } catch (e) {
      console.log(JSON.stringify({
        tag:    "bootstrap_search_error",
        source: "github",
        query,
        error:  String(e?.message || e),
      }));
    }
  }

  for (const query of OPENHUB_QUERIES) {
    if (candidates.length >= IMPORT_LIMIT * 4) break;

    try {
      add(await openHubSearch(env, query, 1));
      add(await openHubSearch(env, query, 2));
    } catch (e) {
      console.log(JSON.stringify({
        tag:    "bootstrap_search_error",
        source: "openhub",
        query,
        error:  String(e?.message || e),
      }));
    }
  }

  candidates.sort((a, b) => b.stars - a.stars);

  return candidates;
};

const repoCandidateFromUrl = async (env, repoUrl, input = {}) => {
  const normalizedRepoUrl = normalizeGitHubRepoUrl(repoUrl);
  if (!normalizedRepoUrl) return null;

  const match = normalizedRepoUrl.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)$/i);
  if (!match) return null;

  const owner = match[1];
  const repo = match[2];

  const details = await githubRepoDetails(env, owner, repo);

  return {
    fullName: `${owner}/${repo}`,
    name: input.name || details?.name || repo,
    description: input.summary || input.description || details?.description || "",
    stars: details?.stars || 0,
    topics: details?.topics || [],
    repoUrl: normalizedRepoUrl,
    iconUrl: input.iconUrl || details?.iconUrl || null,
    assetMatch: input.assetMatch || null,
    preferredAbi: input.preferredAbi || "arm64-v8a",
    adminImport: input.adminImport === true,
  };
};

export const pollGitHubApp = async (env, app) => {
  const normalized = normalizeGitHubRepoUrl(app.repo_url);
  if (!normalized) return null;

  await refreshGitHubMetadataForApp(env, app).catch(() => {});

  const parsed = repoUrlVariants(normalized);
  if (!parsed) return null;

  const release = await githubLatestRelease(env, parsed.owner, parsed.repo);
  if (!release) return null;

  const asset = findApkAsset(release);
  if (!asset) return null;

  if (asset.size && asset.size > MAX_APK_BYTES) return null;

  const versionCode = tagToVersionCode(release.tag_name);
  if (!versionCode) return null;
  const versionName = release.tag_name;

  const existing = await env.api_control_db
    .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND version_code = ?2 LIMIT 1")
    .bind(app.id, versionCode)
    .first();
  if (existing) return null;

  if (Number(app.submission_mode_manual || 0) === 1) return null;

  const apkRes = await fetch(asset.browser_download_url, { headers: { "user-agent": "SafeHaven-Store/1.0" } });
  if (!apkRes.ok) throw new Error(`apk_download_failed:${apkRes.status}`);
  const apkBuffer = await apkRes.arrayBuffer();

  if (apkBuffer.byteLength > MAX_APK_BYTES) return null;

  await uploadBufferToStaging(env, app.package_name, versionCode, apkBuffer);

  const submissionId = await createSubmission(env, {
    appId:       app.id,
    developerId: COMMUNITY_DEVELOPER_ID,
    packageName: app.package_name,
    versionName,
    versionCode,
    stagingKey:  `staging/${app.package_name}/${versionCode}/app.apk`,
  });

  if (!submissionId) throw new Error("submission_create_failed");
  await advanceSubmissionToScan(env, submissionId);

  return true;
};

export async function runGitHubDirectImport(env, input = {}) {
  const repoUrl = (input.repoUrl || "").toString().trim();
  if (!repoUrl) {
    return { imported: false, skipped: true, reason: "repoUrl_required" };
  }

  const candidate = await repoCandidateFromUrl(env, repoUrl, input);
  if (!candidate) {
    return { imported: false, skipped: true, reason: "invalid_github_repo" };
  }

  const outcome = await importCandidate(env, candidate);

  console.log(JSON.stringify({
    tag: "direct_github_import",
    repo: candidate.fullName,
    assetMatch: candidate.assetMatch,
    preferredAbi: candidate.preferredAbi,
    outcome,
  }));

  return {
    repo: candidate.fullName,
    ...outcome,
  };
}

export async function runGitHubReadmeSweep(env, limit = 50) {
  const apps = await getAutoTrackedAppsForReadmeSweep(env, limit);

  const results = {
    checked: 0,
    updated: 0,
    skipped: 0,
    imagesAdded: 0,
    errors: [],
  };

  for (const app of apps) {
    results.checked++;

    try {
      const repoUrl = normalizeGitHubRepoUrl(app.repo_url);
      const match = repoUrl?.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)$/i);

      if (!match) {
        results.skipped++;
        continue;
      }

      const owner = match[1];
      const repo = match[2];

      const details = await githubRepoDetails(env, owner, repo);

      let rawReadme = null;
      let readmeDescription = null;

      try {
        rawReadme = await githubReadmeRaw(env, owner, repo);
        readmeDescription = rawReadme ? stripReadmeToDescription(rawReadme) : null;
      } catch {
        rawReadme = null;
        readmeDescription = null;
      }

      if (!details && !readmeDescription && !rawReadme) {
        results.skipped++;
        continue;
      }

      const summary = normalizeStoreText((details?.description || app.summary || "").slice(0, 200).trim()) || null;
      const description = normalizeStoreText(readmeDescription || details?.description || app.description || null);
      const category = inferCategory(
        {
          fullName: details?.fullName || `${owner}/${repo}`,
          name: details?.name || app.name,
          description: details?.description || summary || "",
          topics: details?.topics || [],
        },
        readmeDescription || ""
      );

      await updateAutoTrackedAppDescription(env, app.id, summary, description, category);

      let updatedApp = await getStoreAppById(env, app.id);
      let screenshotKeys = [];

      if (updatedApp && rawReadme) {
        screenshotKeys = await saveReadmeScreenshotsIfMissing(env, updatedApp, owner, repo, rawReadme);
        updatedApp = await getStoreAppById(env, app.id);
      }

      if (updatedApp) {
        await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
      }

      if (screenshotKeys.length > 0) {
        results.imagesAdded += screenshotKeys.length;
      }

      results.updated++;

      console.log(JSON.stringify({
        tag: "github_readme_sweep_update",
        appId: app.id,
        repo: `${owner}/${repo}`,
        hasReadmeDescription: !!readmeDescription,
        readmeImagesAdded: screenshotKeys.length,
      }));
    } catch (e) {
      results.errors.push({
        appId: app.id,
        repoUrl: app.repo_url,
        error: String(e?.message || e),
      });
    }
  }

  console.log(JSON.stringify({
    tag: "github_readme_sweep_complete",
    checked: results.checked,
    updated: results.updated,
    skipped: results.skipped,
    imagesAdded: results.imagesAdded,
    errors: results.errors.length,
  }));

  return results;
}

export async function runGitHubBootstrapImport(env) {
  const results = {
    imported: 0,
    skipped:  0,
    errors:   [],
    details:  [],
  };

  const candidates = await collectCandidates(env);

  for (const candidate of candidates) {
    if (results.imported >= IMPORT_LIMIT) break;

    try {
      const outcome = await importCandidate(env, candidate);

      if (outcome.imported) {
        results.imported++;

        console.log(JSON.stringify({
          tag:                   "bootstrap_import",
          repo:                  candidate.fullName,
          appId:                 outcome.appId,
          submissionId:          outcome.submissionId,
          packageName:           outcome.packageName,
          versionCode:           outcome.versionCode,
          hasIcon:               outcome.hasIcon,
          hasReadmeDescription:  outcome.hasReadmeDescription,
        }));
      } else {
        results.skipped++;
      }

      results.details.push({ repo: candidate.fullName, ...outcome });
    } catch (e) {
      results.errors.push({
        repo:  candidate.fullName,
        error: String(e?.message || e),
      });
    }
  }

  console.log(JSON.stringify({
    tag:      "bootstrap_import_complete",
    imported: results.imported,
    skipped:  results.skipped,
    errors:   results.errors.length,
  }));

  return results;
}