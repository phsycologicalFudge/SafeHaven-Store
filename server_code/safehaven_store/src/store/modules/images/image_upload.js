import { getPresignedImageUploadUrl, imageKey } from "../../storage.js";
import { normaliseIcon } from "./icon_normalise.js";
import { normaliseScreenshot } from "./screenshot_normalise.js";

const ALLOWED_TYPES = ["image/png", "image/jpeg", "image/webp"];

const sniffMagicType = (bytes) => {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return "image/webp";
  return null;
};

const sniffContentType = (url, headerType) => {
  const h = (headerType || "").split(";")[0].trim().toLowerCase();
  if (ALLOWED_TYPES.includes(h)) return h;
  if (/\.png(?:[?#].*)?$/i.test(url))  return "image/png";
  if (/\.jpe?g(?:[?#].*)?$/i.test(url)) return "image/jpeg";
  if (/\.webp(?:[?#].*)?$/i.test(url)) return "image/webp";
  return null;
};

const putNormalisedImage = async (env, packageName, slot, buffer, isIcon, fallbackType) => {
  let normed;
  let contentType = "image/png";
  try {
    normed = isIcon
      ? await normaliseIcon(buffer)
      : await normaliseScreenshot(buffer);
  } catch {
    normed = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    contentType = sniffMagicType(normed) || (ALLOWED_TYPES.includes(fallbackType) ? fallbackType : null);
    if (!contentType) return null;
  }

  const url = await getPresignedImageUploadUrl(env, packageName, slot, 300);
  const res = await fetch(url, {
    method:  "PUT",
    headers: { "content-type": contentType },
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
  const limit  = Number.isFinite(maxBytes) ? maxBytes : 8 * 1024 * 1024;
  if (!buffer.byteLength || buffer.byteLength > limit) return null;

  const isIcon = slot === "icon";
  return putNormalisedImage(env, packageName, slot, buffer, isIcon, contentType);
};

export const uploadImageFromBuffer = async (env, packageName, slot, buffer) => {
  if (!buffer || !buffer.byteLength) return null;
  const isIcon       = slot === "icon";
  const fallbackType = sniffMagicType(buffer);
  return putNormalisedImage(env, packageName, slot, buffer, isIcon, fallbackType);
};