import { getLiteIndex } from "../data/index_reader.ts";
import { renderCatalogueHome } from "../templates/catalogue_home.ts";
import { brandIconUrl } from "../lib/shared.ts";

export const handleCatalogueHomeRoute = async (request, env, path) => {
  if (path !== "/" && path !== "") return null;

  const index = await getLiteIndex(env);
  const html = renderCatalogueHome(index, brandIconUrl(index));

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
    },
  });
};
