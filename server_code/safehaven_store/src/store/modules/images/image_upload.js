import { getPresignedImageUploadUrl, imageKey } from "../storage.js";
import { normaliseIcon } from "./icon_normalise.js";
import { normaliseScreenshot } from "./screenshot_normalise.js";

const ALLOWED_TYPES = ["image/png", "image/jpeg", "image/webp"];

const sniffContentType = (url, headerType) => {
  const h = (headerType || "").split(";")[0].trim().toLowerCase();
  if (ALLOWED_TYPES.includes(h)) return h;
  if (/\.png(?:[?#].*)?$/i.test(url))  return "image/png";
  if (/\.jpe?g(?:[?#].*)?$/i.test(url)) return "image/jpeg";
  if (/\.webp(?:[?#].*)?$/i.test(url)) return "image/webp";
  return null;
};

const putNormalisedImage = async (env, packageName, slot, buffer, isIcon) => {
  let normed;
  try {
    normed = isIcon
      ? await normaliseIcon(buffer)
      : await normaliseScreenshot(buffer);
  } catch {
    normed = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  }

  const url = await getPresignedImageUploadUrl(env, packageName, slot, 300);
  const res = await fetch(url, {
    method:  "PUT",
    headers: { "content-type": "image/png" },
    body:    normed,
  });
  if (!res.ok) return null;
  return imageKey(packageName, slot);
};

export const uploadImageFromUrl = async (env, packageName, slot, imageUrl, maxBytes) => {
  let res;
  try {
    res = await fetch(imageUrl, { headers: { "user-agent": "SafeHaven-Store/1.0" } });
  } catch {
    return null;
  }
  if (!res.ok) return null;

  const contentType = sniffContentType(imageUrl, res.headers.get("content-type"));
  if (!contentType) return null;

  const buffer = await res.arrayBuffer();
  if (!buffer.byteLength || buffer.byteLength > maxBytes) return null;

  const isIcon = slot === "icon";
  return putNormalisedImage(env, packageName, slot, buffer, isIcon);
};

export const uploadImageFromBuffer = async (env, packageName, slot, buffer) => {
  if (!buffer || !buffer.byteLength) return null;
  const isIcon = slot === "icon";
  return putNormalisedImage(env, packageName, slot, buffer, isIcon);
};