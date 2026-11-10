// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

export const corsHeaders = {
  "access-control-allow-origin":  "*",
  "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
  "access-control-allow-headers": "authorization,content-type,x-vps-auth",
};

export const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders },
  });

export const readJson = async (req) => {
  const ct = req.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) return null;
  try { return await req.json(); } catch { return null; }
};

export const unauthorized = () => json({ error: "unauthorized" }, 401);

export const forbidden    = () => json({ error: "forbidden" }, 403);

export const badRequest   = (msg = "bad_request") => json({ error: msg }, 400);

export const notFound     = () => json({ error: "not_found" }, 404);

export const isScannerAuth = (env, request) => {
  const provided = (request.headers.get("x-vps-auth") || "").trim();
  const secret   = (env.SH_SCANNER_SECRET || "").trim();
  return !!(provided && secret && provided === secret);
};

export const isAdminSecretAuth = (env, request) => {
  const provided = (request.headers.get("authorization") || "").trim();
  const secret   = (env.SH_ADMIN_SECRET || "").trim();
  return !!(provided && secret && provided === secret);
};
