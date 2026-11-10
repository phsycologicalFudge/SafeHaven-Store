import { getStoreAppByPackage, getStoreAppById, setAppRepoVerified, setAppSigningKeyHash, setAppStatus, setAppCategory, createSubmission, advanceSubmissionToScan, APP_STATUS, createUnclaimedStoreApp, setAppLastRepoCheck, setAppClaimed } from "../db/index.js";
import { getIndex, putIndexWithChangelog } from "../storage/index.js";
import { refreshGitHubMetadataForApp } from "../../modules/git_store_job.js";
import { runGitLabDirectImport } from "../../modules/gitlab_store_job.js";
import { runCodebergDirectImport } from "../../modules/codeberg_store_job.js";
import { normalizeStoreText, COMMUNITY_DEVELOPER_ID } from "../../helpers/store_helpers.js";
import { parseGitHubRepo, githubLatestRelease, findApkAsset, tagToVersionCode, uploadBufferToStaging } from "../../helpers/github_helpers.js";
import { json, readJson, unauthorized, forbidden, badRequest, notFound } from "../http/responses.js";
import { getVersionConflictState, clearReplaceableSubmissions } from "../services/version_conflict.js";

const MAX_APK_BYTES = 100 * 1024 * 1024;

export const routes = [
  {
    methods: ["POST"],
    match: (path) => path === "/store/track",
    handle: async ({ request, env }) => {
      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const repoUrl  = (body.repoUrl || "").toString().trim();
      if (!repoUrl) return badRequest("repoUrl_required");

      const urlLower   = repoUrl.toLowerCase();
      const isGitHub   = urlLower.includes("github.com");
      const isGitLab   = urlLower.includes("gitlab.com");
      const isCodeberg = urlLower.includes("codeberg.org");

      if (!isGitHub && !isGitLab && !isCodeberg) {
        return badRequest("unsupported_platform");
      }

      if (isGitLab || isCodeberg) {
        const outcome = isGitLab
          ? await runGitLabDirectImport(env, { repoUrl })
          : await runCodebergDirectImport(env, { repoUrl });

        if (outcome.imported) {
          return json({
            ok:           true,
            appId:        outcome.appId,
            submissionId: outcome.submissionId,
            packageName:  outcome.packageName,
            versionCode:  outcome.versionCode,
          }, 201);
        }

        const reasonMap = {
          already_tracked:             [409, "already_tracked"],
          placeholder_collision:       [409, "already_tracked"],
          no_stable_release:           [422, "no_stable_release_found"],
          no_matching_apk_asset:       [422, "no_apk_asset_in_release"],
          apk_too_large:               [422, "apk_too_large"],
          apk_too_large_post_download: [422, "apk_too_large"],
          invalid_gitlab_url:          [400, "invalid_repo_url"],
          invalid_codeberg_url:        [400, "invalid_repo_url"],
          unparseable_version:         [422, "unsupported_release_tag"],
          apk_download_error:          [502, "apk_download_failed"],
          apk_download_failed:         [502, "apk_download_failed"],
          staging_failed:              [500, "staging_upload_failed"],
        };

        const code = (outcome.reason || "").split(":")[0];
        if (code !== outcome.reason) console.log(JSON.stringify({ tag: "track_error", repoUrl, reason: outcome.reason }));
        const [status, error] = reasonMap[code] || [422, code || "import_failed"];
        return json({ error, reason: code }, status);
      }

      const summary     = normalizeStoreText(body.summary);
      const description = normalizeStoreText(body.description);
      const category    = (body.category || "").toString().trim() || null;

      const gh = parseGitHubRepo(repoUrl);
      if (!gh) return badRequest("invalid_repo_url");

      const name        = (body.name        || "").toString().trim() || gh.repo;
      const packageName = (body.packageName || "").toString().trim() || `pending.${gh.owner}.${gh.repo}`;

      let release;
      try {
        release = await githubLatestRelease(env, gh.owner, gh.repo);
      } catch (e) {
        console.log(JSON.stringify({ tag: "track_error", repoUrl, stage: "github_fetch", error: String(e?.message || e) }));
        return json({ error: "github_fetch_failed" }, 502);
      }
      if (!release) return json({ error: "no_stable_release_found" }, 422);

      const asset = findApkAsset(release);
      if (!asset) return json({ error: "no_apk_asset_in_release" }, 422);

      if (asset.size && asset.size > MAX_APK_BYTES) return json({ error: "apk_too_large" }, 422);

      const versionName = release.tag_name;
      const versionCode = tagToVersionCode(release.tag_name);
      if (!versionCode) return json({ error: "unsupported_release_tag", tag: release.tag_name }, 422);

      const existing = await getStoreAppByPackage(env, packageName);
      let appId = existing?.id || null;

      if (!appId) {
        appId = await createUnclaimedStoreApp(env, { packageName, name, summary, description, repoUrl });
        if (!appId) return json({ error: "app_create_failed" }, 500);
        try {
          const newApp = await getStoreAppById(env, appId);
          if (newApp) await refreshGitHubMetadataForApp(env, newApp, gh.owner, gh.repo);
        } catch {}
      } else if (existing.status !== APP_STATUS.ACTIVE) {
        await setAppStatus(env, appId, APP_STATUS.ACTIVE);
      }

      const versionState = await getVersionConflictState(
        env,
        appId,
        versionCode
      );

      if (versionState.type === "live") {
        return json({
          error: "already_live",
          appId,
          submissionId: versionState.submission.id,
          versionName,
          versionCode,
        }, 409);
      }

      if (versionState.type === "in_flight") {
        return json({
          error: "already_pending",
          appId,
          submissionId: versionState.submission.id,
          status: versionState.submission.status,
          versionName,
          versionCode,
        }, 409);
      }

      if (versionState.type === "cooldown") {
        return json({
          error: "version_retry_cooldown",
          appId,
          versionName,
          versionCode,
          retryAfter: versionState.retryAfter,
        }, 429);
      }

      await clearReplaceableSubmissions(
        env,
        versionState.replaceable
      );

      let apkBuffer;
      try {
        const apkRes = await fetch(asset.browser_download_url, {
          headers: { "user-agent": "SafeHaven-Store/1.0" },
        });
        if (!apkRes.ok) throw new Error(`apk_download_failed:${apkRes.status}`);
        apkBuffer = await apkRes.arrayBuffer();
      } catch (e) {
        console.log(JSON.stringify({ tag: "track_error", repoUrl, stage: "apk_download", error: String(e?.message || e) }));
        return json({ error: "apk_download_failed" }, 502);
      }

      if (apkBuffer.byteLength > MAX_APK_BYTES) return json({ error: "apk_too_large" }, 422);

      if (category) await setAppCategory(env, appId, category);

      try {
        await uploadBufferToStaging(env, packageName, versionCode, apkBuffer);
      } catch (e) {
        console.log(JSON.stringify({ tag: "track_error", repoUrl, stage: "staging_upload", error: String(e?.message || e) }));
        return json({ error: "staging_upload_failed" }, 500);
      }

      const submissionId = await createSubmission(env, {
        appId,
        developerId: COMMUNITY_DEVELOPER_ID,
        packageName,
        versionName,
        versionCode,
        stagingKey:  `staging/${packageName}/${versionCode}/app.apk`,
      });
      if (!submissionId) return json({ error: "submission_create_failed" }, 500);

      await advanceSubmissionToScan(env, submissionId);
      await setAppLastRepoCheck(env, appId);

      return json({ ok: true, appId, submissionId, versionName, versionCode }, 201);
    },
  },
  {
    methods: ["GET"],
    match: (path) => path.startsWith("/store/track/"),
    handle: async ({ env, path }) => {
      const packageName = decodeURIComponent(path.replace("/store/track/", "")).trim();
      if (!packageName) return notFound();
      const app = await getStoreAppByPackage(env, packageName);
      if (!app) return notFound();
      return json({
        appId:         app.id,
        packageName:   app.package_name,
        name:          app.name,
        repoUrl:       app.repo_url,
        claimed:       !!app.claimed,
        trustLevel:    app.trust_level,
        signingFlag:   app.signing_flag || null,
        lastRepoCheck: app.last_repo_check || null,
        upstream:      app.upstream || null,
      });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/track\/[^/]+\/claim$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      if (!me.developerEnabled) return forbidden();

      const appId = path.replace("/store/track/", "").replace("/claim", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();

      const isFdroid = app.upstream === "fdroid";

      if (app.claimed && !isFdroid) return json({ error: "already_claimed" }, 409);

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const providedHash = (body.signingKeyHash || "").toString().trim();

      if (isFdroid) {
        if (!providedHash) return badRequest("signingKeyHash_required");
      }

      const gh = parseGitHubRepo(app.repo_url);
      if (!gh) return json({ error: "repo_not_verifiable" }, 422);

      const challengeRes = await fetch(
        `https://raw.githubusercontent.com/${gh.owner}/${gh.repo}/HEAD/.safehaven`,
        { headers: { "user-agent": "SafeHaven-Store/1.0" } }
      );
      if (!challengeRes.ok) return json({ error: "challenge_file_not_found" }, 403);
      const challengeBody = (await challengeRes.text()).trim();
      if (challengeBody !== app.repo_token) return json({ error: "challenge_mismatch" }, 403);

      await setAppClaimed(env, appId, me.id);
      await setAppRepoVerified(env, appId, true);

      if (isFdroid) {
        await setAppSigningKeyHash(env, appId, providedHash);
        await env.api_control_db.prepare("DELETE FROM store_submissions WHERE app_id = ?1").bind(appId).run();
        await env.api_control_db.prepare("UPDATE store_apps SET upstream = NULL WHERE id = ?1").bind(appId).run();

        const index = await getIndex(env);
        const idxApp = index.apps.find(a => a.packageName === app.package_name);
        if (idxApp) {
          idxApp.versions = [];
          idxApp.upstream = null;
          await putIndexWithChangelog(env, index);
        }
      }

      return json({ ok: true, claimed: true });
    },
  },
];
