import { handleAppPageRoute } from "./routes/app_page_route.ts";
import { handleCatalogueHomeRoute } from "./routes/catalogue_home_route.ts";
import { handleSearchRoute } from "./routes/search_route.ts";
import { handleUnlockRoute, isUnlocked } from "./routes/unlock_route.ts";
import { renderUnderConstruction } from "./templates/under_construction.ts";
import { getLiteIndex } from "./data/index_reader.ts";
import themeCss from "./styles/theme.css.ts";
import componentsCss from "./styles/components.css.ts";
import badgeSvg from "./assets/badge.svg.ts";
import badgePngBase64 from "./assets/badge.png.ts";

const css = (body) =>
  new Response(body, {
    headers: {
      "content-type": "text/css; charset=utf-8",
      "cache-control": "public, max-age=3600",
    },
  });

const svg = (body) =>
  new Response(body, {
    headers: {
      "content-type": "image/svg+xml; charset=utf-8",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });

const base64ToBytes = (base64) => {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
};

const png = (base64Body) =>
  new Response(base64ToBytes(base64Body), {
    headers: {
      "content-type": "image/png",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });

const isUnderConstruction = (env) => {
  return (env.STORE_UNDER_CONSTRUCTION || "").toString().trim().toLowerCase() === "false";
};

const SAFEHAVEN_CERT_FINGERPRINT =
  "9C:67:F4:22:48:88:F6:0E:09:3C:F7:EA:B9:B1:94:E6:D4:CD:73:BB:11:31:36:38:C4:7B:17:F0:D5:F3:4E:C4";

const assetLinksJson = () =>
  new Response(
    JSON.stringify([
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: {
          namespace: "android_app",
          package_name: "com.colourswift.safehaven",
          sha256_cert_fingerprints: [SAFEHAVEN_CERT_FINGERPRINT],
        },
      },
    ]),
    {
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "public, max-age=3600",
      },
    }
  );

export const handleStoreWeb = async (request, env, path) => {
  if (request.method === "GET" && path === "/.well-known/assetlinks.json") {
    return assetLinksJson();
  }

  if (request.method === "GET" && path === "/css/theme.css") {
    return css(themeCss);
  }

  if (request.method === "GET" && path === "/css/components.css") {
    return css(componentsCss);
  }

  if (request.method === "GET" && path === "/badge.svg") {
    return svg(badgeSvg);
  }

  if (request.method === "GET" && path === "/badge.png") {
    return png(badgePngBase64);
  }

  const unlockRes = await handleUnlockRoute(request, env, path);
  if (unlockRes) return unlockRes;

  if (request.method === "GET" && isUnderConstruction(env)) {
    const unlocked = await isUnlocked(request, env);

    if (!unlocked) {
      const index = await getLiteIndex(env);
      const url = new URL(request.url);
      const wrongPassword = url.searchParams.get("wrong") === "1";
      const html = renderUnderConstruction(index, wrongPassword);
      return new Response(html, {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }
  }

  if (request.method === "GET") {
    const searchRes = await handleSearchRoute(request, env, path);
    if (searchRes) return searchRes;

    const homeRes = await handleCatalogueHomeRoute(request, env, path);
    if (homeRes) return homeRes;

    const appRes = await handleAppPageRoute(request, env, path);
    if (appRes) return appRes;
  }

  return null;
};