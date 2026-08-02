const COOKIE_NAME = "sh_store_session";
const SESSION_TTL_SECONDS = 60 * 60 * 6;

const randomToken = () => {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
};

const timingSafeEqual = (a, b) => {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
};

const parseCookies = (request) => {
  const header = request.headers.get("cookie") || "";
  const map = {};
  header.split(";").forEach((part) => {
    const idx = part.indexOf("=");
    if (idx === -1) return;
    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();
    if (key) map[key] = value;
  });
  return map;
};

export const isUnlocked = async (request, env) => {
  if (!env.STORE_INDEX_KV) return false;
  const token = parseCookies(request)[COOKIE_NAME];
  if (!token) return false;
  const stored = await env.STORE_INDEX_KV.get(`session:${token}`);
  return stored === "unlocked";
};

export const handleUnlockRoute = async (request, env, path) => {
  if (path !== "/unlock" || request.method !== "POST") return null;

  const url = new URL(request.url);
  const expected = (env.STORE_UNLOCK_PASSWORD || "").toString();
  const form = await request.formData();
  const submitted = (form.get("password") || "").toString();

  if (!expected || !timingSafeEqual(submitted, expected)) {
    return Response.redirect(`${url.origin}/?wrong=1`, 303);
  }

  const token = randomToken();
  if (env.STORE_INDEX_KV) {
    await env.STORE_INDEX_KV.put(`session:${token}`, "unlocked", {
      expirationTtl: SESSION_TTL_SECONDS,
    });
  }

  const headers = new Headers();
  headers.set("location", `${url.origin}/`);
  headers.append(
    "set-cookie",
    `${COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Lax`
  );
  return new Response(null, { status: 303, headers });
};
