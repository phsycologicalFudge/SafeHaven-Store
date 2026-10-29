import { getStoreAppByPackage, getStoreAppById, getStoreAppsByDeveloper, createStoreApp, setAppRepoVerified, setAppCategory, setAppImages, getSubmissionsByApp, APP_STATUS, setAppClaimed } from "../db/index.js";
import { addOrUpdateApp, getPresignedImageUploadUrl, imageKey, IMAGE_SLOTS, CATEGORIES } from "../storage/index.js";
import { uploadImageFromBuffer } from "../../modules/images/image_upload.js";
import { nowUnix, normalizeStoreText, parseScreenshots, buildIndexAppEntry, COMMUNITY_DEVELOPER_ID } from "../../helpers/store_helpers.js";
import { json, readJson, unauthorized, forbidden, badRequest, notFound } from "../http/responses.js";

const REPO_VERIFY_FILE = ".safehaven";

const buildRawFileUrl = (repoUrl) => {
  const url = (repoUrl || "").toString().trim().replace(/\/$/, "").replace(/\.git$/, "");
  const gh  = url.match(/^https?:\/\/github\.com\/([^/]+\/[^/]+)$/);
  if (gh) return `https://raw.githubusercontent.com/${gh[1]}/HEAD/${REPO_VERIFY_FILE}`;
  const gl  = url.match(/^https?:\/\/gitlab\.com\/([^/]+\/[^/]+)$/);
  if (gl) return `https://gitlab.com/${gl[1]}/-/raw/HEAD/${REPO_VERIFY_FILE}`;
  const cb  = url.match(/^https?:\/\/codeberg\.org\/([^/]+\/[^/]+)$/);
  if (cb) return `https://codeberg.org/${cb[1]}/raw/branch/main/${REPO_VERIFY_FILE}`;
  return null;
};

export const routes = [
  {
    methods: ["POST"],
    match: (path) => path === "/store/apps",
    handle: async ({ request, env, requireDeveloper }) => {
      const me = await requireDeveloper();
      if (me === null) return unauthorized();
      if (me === false) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const packageName = (body.packageName || "").toString().trim();
      const name        = (body.name        || "").toString().trim();
      const repoUrl     = (body.repoUrl     || "").toString().trim();
      const summary     = normalizeStoreText(body.summary);
      const description = normalizeStoreText(body.description);

      if (!packageName) return badRequest("missing_packageName");
      if (!name)        return badRequest("missing_name");
      if (!repoUrl)     return badRequest("missing_repoUrl");

      if (!/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(packageName)) {
        return badRequest("invalid_packageName");
      }

      const existing = await getStoreAppByPackage(env, packageName);
      if (existing) {
        if (!existing.claimed && existing.auto_tracked) {
          return json({ error: "package_already_registered", claimable: true, appId: existing.id, repoToken: existing.repo_token }, 409);
        }
        return json({ error: "package_already_registered", claimable: false }, 409);
      }

      const result = await createStoreApp(env, {
        developerId: me.id, packageName, name, summary, description, repoUrl,
      });
      if (!result) return json({ error: "create_failed" }, 500);

      return json({ ok: true, appId: result.id, repoToken: result.repoToken }, 201);
    },
  },
  {
    methods: ["GET"],
    match: (path) => path === "/store/apps",
    handle: async ({ env, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const apps = await getStoreAppsByDeveloper(env, me.id);
      return json({ apps });
    },
  },
  {
    methods: ["GET"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+$/),
    handle: async ({ env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();
      if (app.developer_id !== me.id && !me.admin) return forbidden();
      const submissions = await getSubmissionsByApp(env, appId);
      return json({ app, submissions });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/verify-repo$/),
    handle: async ({ env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/verify-repo", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                       return notFound();
      if (app.developer_id !== me.id) return forbidden();

      const rawUrl = buildRawFileUrl(app.repo_url);
      if (!rawUrl) return badRequest("unsupported_repo_host");

      let remoteContent;
      try {
        const res = await fetch(rawUrl, { headers: { "user-agent": "SafeHaven-Verifier/1.0" } });
        if (!res.ok) return json({ ok: false, reason: "file_not_found" }, 422);
        remoteContent = (await res.text()).trim();
      } catch {
        return json({ ok: false, reason: "fetch_failed" }, 422);
      }

      if (remoteContent !== (app.repo_token || "").trim()) {
        return json({ ok: false, reason: "token_mismatch" }, 422);
      }

      await setAppRepoVerified(env, appId, true);
      await setAppClaimed(env, appId, app.developer_id);
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/image-upload-urls$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/image-upload-urls", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                       return notFound();
      if (app.developer_id !== me.id && app.developer_id !== COMMUNITY_DEVELOPER_ID && !me.admin) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const requestedSlots = Array.isArray(body.slots) ? body.slots : [];
      const validSlots     = requestedSlots.filter((s) => IMAGE_SLOTS.includes(s));
      if (!validSlots.length) return badRequest("no_valid_slots");

      const urls = {};
      for (const slot of validSlots) {
        urls[slot] = await getPresignedImageUploadUrl(env, app.package_name, slot);
      }
      return json({ ok: true, urls });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/images$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/images", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                       return notFound();
      if (app.developer_id !== me.id && app.developer_id !== COMMUNITY_DEVELOPER_ID && !me.admin) return forbidden();

      const body = await readJson(request);
      if (!body) return badRequest("json_required");

      const iconUploaded    = !!body.iconUploaded;
      const screenshotSlots = Array.isArray(body.screenshotSlots)
        ? body.screenshotSlots.map(Number).filter((n) => Number.isInteger(n) && n >= 1 && n <= 6)
        : [];

      const newIconKey          = iconUploaded ? imageKey(app.package_name, "icon") : (app.icon_key || null);
      const existingScreenshots = parseScreenshots(app.screenshots_json);
      const newScreenshotKeys   = screenshotSlots.length
        ? screenshotSlots.map((n) => imageKey(app.package_name, `screenshot_${n}`))
        : existingScreenshots;

      await setAppImages(env, appId, { iconKey: newIconKey, screenshotKeys: newScreenshotKeys });

      const updatedApp = await getStoreAppById(env, appId);
      if (updatedApp && updatedApp.status === APP_STATUS.ACTIVE) {
        const liveSubmission = await env.api_control_db
          .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND status = 'live' LIMIT 1")
          .bind(appId)
          .first();
        if (liveSubmission) {
          await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
        }
      }
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/upload-image$/),
    handle: async ({ request, env, url, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/upload-image", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app)                                                                         return notFound();
      if (app.developer_id !== me.id && !me.admin)                                     return forbidden();

      const slot        = (url.searchParams.get("slot") || "").trim();
      const validSlots  = ["icon", "screenshot_1", "screenshot_2", "screenshot_3", "screenshot_4", "screenshot_5", "screenshot_6"];
      if (!validSlots.includes(slot))                                                   return badRequest("invalid_slot");

      const contentType = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      if (!["image/png", "image/jpeg", "image/webp"].includes(contentType))            return badRequest("invalid_content_type");

      const buffer = await request.arrayBuffer();
      if (!buffer.byteLength)                                                           return badRequest("empty_body");
      if (buffer.byteLength > 2 * 1024 * 1024)                                         return badRequest("image_too_large");

      const key = await uploadImageFromBuffer(env, app.package_name, slot, buffer);
      if (!key) return json({ error: "upload_failed" }, 500);

      const existingScreenshots = parseScreenshots(app.screenshots_json);
      const isIcon              = slot === "icon";
      const newIconKey          = isIcon ? key : (app.icon_key || null);
      const newScreenshotKeys   = isIcon
        ? existingScreenshots
        : (() => {
            const updated = [...existingScreenshots];
            const idx     = parseInt(slot.replace("screenshot_", ""), 10) - 1;
            updated[idx]  = key;
            return updated.filter(Boolean);
          })();

      await setAppImages(env, appId, { iconKey: newIconKey, screenshotKeys: newScreenshotKeys });

      const updatedApp = await getStoreAppById(env, appId);
      if (updatedApp && updatedApp.status === APP_STATUS.ACTIVE) {
        const liveSubmission = await env.api_control_db
          .prepare("SELECT id FROM store_submissions WHERE app_id = ?1 AND status = 'live' LIMIT 1")
          .bind(appId)
          .first();
        if (liveSubmission) await addOrUpdateApp(env, buildIndexAppEntry(env, updatedApp));
      }

      return json({ ok: true, key });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/category$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/category", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();
      if (app.developer_id !== me.id) return forbidden();
      const body = await readJson(request);
      if (!body) return badRequest("json_required");
      const category = (body.category || "").toString().trim() || null;
      if (category && !Object.keys(CATEGORIES).includes(category)) return badRequest("invalid_category");
      await setAppCategory(env, appId, category);
      if (app.status === APP_STATUS.ACTIVE) {
        await addOrUpdateApp(env, { ...buildIndexAppEntry(env, app), category });
      }
      return json({ ok: true });
    },
  },
  {
    methods: ["POST"],
    match: (path) => path.match(/^\/store\/apps\/[^/]+\/submission-mode$/),
    handle: async ({ request, env, path, requireUser }) => {
      const me = await requireUser();
      if (!me) return unauthorized();
      const appId = path.replace("/store/apps/", "").replace("/submission-mode", "").trim();
      const app   = await getStoreAppById(env, appId);
      if (!app) return notFound();
      if (app.developer_id !== me.id) return forbidden();
      const body = await readJson(request);
      if (!body) return badRequest("json_required");
      const manual = body.manual === true ? 1 : 0;
      await env.api_control_db
        .prepare("UPDATE store_apps SET submission_mode_manual = ?2, updated_at = ?3 WHERE id = ?1")
        .bind(appId, manual, nowUnix())
        .run();
      return json({ ok: true, manual: manual === 1 });
    },
  },
];
