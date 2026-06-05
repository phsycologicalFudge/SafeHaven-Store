import { getPresignedStagingUploadUrl } from "../storage.js";

export { normalizeAssetText, apkAssetsOf, scoreApkAsset, findApkAsset, tagToVersionCode } from "./apk_helpers.js";

export const githubHeaders = (env) => {
  const token = (env.GITHUB_TOKEN || "").trim();
  return {
    "user-agent": "SafeHaven-Store/1.0",
    accept:       "application/vnd.github+json",
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  };
};

export const normalizeGitHubRepoUrl = (repoUrl) => {
  const clean = (repoUrl || "").toString().trim().replace(/\.git$/, "").replace(/\/$/, "");
  const m = clean.match(/^https?:\/\/github\.com\/([^/]+)\/([^/]+)$/i);
  if (!m) return null;
  return `https://github.com/${m[1]}/${m[2]}`;
};

export const parseGitHubRepo = (repoUrl) => {
  const url = (repoUrl || "").toString().trim().replace(/\/$/, "").replace(/\.git$/, "");
  const m = url.match(/^https?:\/\/github\.com\/([^/]+)\/([^/]+)$/);
  return m ? { owner: m[1], repo: m[2] } : null;
};

export const repoUrlVariants = (repoUrl) => {
  const normal = normalizeGitHubRepoUrl(repoUrl);
  if (!normal) return [];
  return [normal, `${normal}/`, `${normal}.git`];
};

export const githubLatestRelease = async (env, owner, repo) => {
  const res = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/releases/latest`,
    { headers: githubHeaders(env) }
  );
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`github_api_error:${res.status}`);
  const data = await res.json();
  if (data.prerelease || data.draft) return null;
  return data;
};

export const uploadBufferToStaging = async (env, packageName, versionCode, buffer) => {
  const url = await getPresignedStagingUploadUrl(env, packageName, versionCode, 300);
  const res = await fetch(url, {
    method:  "PUT",
    headers: { "content-type": "application/vnd.android.package-archive" },
    body:    buffer,
  });
  if (!res.ok) throw new Error(`staging_upload_failed:${res.status}`);
};
