export const normalizeAssetText = (value) =>
  (value || "").toString().trim().toLowerCase();

export const apkAssetsOf = (release) =>
  (release?.assets || []).filter((asset) =>
    asset?.name?.toLowerCase().endsWith(".apk") &&
    asset.state === "uploaded" &&
    asset.browser_download_url &&
    !/debug|beta|alpha|snapshot|unsigned|source|src/i.test(asset.name)
  );

export const scoreApkAsset = (asset, options = {}) => {
  const name = normalizeAssetText(asset.name);
  let score = 0;

  if (options.assetMatch) {
    const match = normalizeAssetText(options.assetMatch);
    if (name === match) return 1000;
    if (name.includes(match)) score += 50;
  }

  if (/arm64-v8a|aarch64/.test(name)) score += 30;
  else if (/-arm64[-_]/.test(name)) score += 25;
  else if (/universal|noarch|all|generic/.test(name)) score += 15;
  else if (!/armeabi-v7a|x86|x86_64|mips/.test(name)) score += 10;

  if (/release|stable|prod/.test(name)) score += 5;
  if (/signed/.test(name)) score += 3;

  if (/armeabi-v7a/.test(name)) score -= 20;
  if (/x86|x86_64|mips/.test(name)) score -= 30;
  if (/debug|beta|alpha|snapshot|unsigned/.test(name)) score -= 50;

  if (asset.size) {
    if (asset.size > 5 * 1024 * 1024 && asset.size < 150 * 1024 * 1024) score += 2;
  }

  return score;
};

export const findApkAsset = (release, options = {}) => {
  const assets = apkAssetsOf(release);
  if (!assets.length) return null;

  const scored = assets
    .map((asset) => ({ asset, score: scoreApkAsset(asset, options) }))
    .sort((a, b) => b.score - a.score);

  const topScore = scored[0]?.score ?? -Infinity;
  const candidates = scored.filter((s) => s.score === topScore && s.score > 0);

  if (candidates.length === 1) return candidates[0].asset;

  const preferred = candidates.find((c) =>
    /arm64-v8a|aarch64/.test(normalizeAssetText(c.asset.name))
  );
  if (preferred) return preferred.asset;

  const generic = candidates.find((c) =>
    !/armeabi-v7a|x86|x86_64|mips|universal|noarch/.test(normalizeAssetText(c.asset.name))
  );
  if (generic) return generic.asset;

  return candidates[0]?.asset || null;
};

export const tagToVersionCode = (tag) => {
  const clean = (tag || "")
    .toString()
    .trim()
    .replace(/^release[-_/]*/i, "")
    .replace(/^version[-_/]*/i, "")
    .replace(/^v/i, "");

  const match = clean.match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-._](\d+))?$/);
  if (!match) return null;

  const major = Number(match[1] || 0);
  const minor = Number(match[2] || 0);
  const patch = Number(match[3] || 0);
  const build = Number(match[4] || 0);

  if (
    !Number.isSafeInteger(major) ||
    !Number.isSafeInteger(minor) ||
    !Number.isSafeInteger(patch) ||
    !Number.isSafeInteger(build)
  ) return null;

  if (major < 0 || minor < 0 || patch < 0 || build < 0) return null;
  if (major > 9999 || minor > 999 || patch > 999 || build > 99) return null;

  return major * 100000000 + minor * 100000 + patch * 100 + build;
};

export const versionNameToVersionCode = (versionName) => {
  const clean = (versionName || "").toString().trim().replace(/^v/i, "");
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
  ) return null;

  if (major < 0 || minor < 0 || patch < 0 || build < 0) return null;
  if (major > 9999 || minor > 999 || patch > 999 || build > 99) return null;

  return major * 100000000 + minor * 100000 + patch * 100 + build;
};

export const assetNameToVersionName = (assetName) => {
  const name = (assetName || "").toString().trim();
  const versionMatch = name.match(/(?:^|[-_])v(\d+(?:[._]\d+){1,5}(?:[+._-][a-z0-9.]+)?)(?=\.apk$|[-_])/i);
  if (!versionMatch) return null;
  return `v${versionMatch[1].replace(/_/g, ".")}`;
};

export const uploadBufferToStaging = async (env, packageName, versionCode, buffer, getPresignedStagingUploadUrl) => {
  const url = await getPresignedStagingUploadUrl(env, packageName, versionCode, 300);
  const res = await fetch(url, {
    method: "PUT",
    headers: { "content-type": "application/vnd.android.package-archive" },
    body: buffer,
  });
  if (!res.ok) throw new Error(`staging_upload_failed:${res.status}`);
};
