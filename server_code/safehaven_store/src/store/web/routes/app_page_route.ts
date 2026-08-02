import { getAppDetail } from "../data/index_reader.ts";
import { renderAppPage } from "../templates/app_page.ts";

export const handleAppPageRoute = async (request, env, path) => {
  const match = path.match(/^\/app\/([^/]+)\/?$/);
  if (!match) return null;

  const packageName = decodeURIComponent(match[1]).trim();
  if (!packageName) return null;

  const { app, lite } = await getAppDetail(env, packageName);

  if (!app) {
    return new Response("App not found", { status: 404 });
  }

  const url = new URL(request.url);
  const baseUrl = `${url.protocol}//${url.host}`;
  const html = renderAppPage(app, baseUrl, lite);

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
    },
  });
};
