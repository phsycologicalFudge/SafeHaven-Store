import { normalizeStoreText } from "./store_helpers.js";

export const WHATS_NEW_MAX_CHARS = 4000;

const truncate = (text) => {
  if (!text) return null;
  if (text.length <= WHATS_NEW_MAX_CHARS) return text;
  return text.slice(0, WHATS_NEW_MAX_CHARS).trim() + "…";
};

export const releaseNotesFromGitHub = (release) =>
  truncate(normalizeStoreText(release?.body));

export const releaseNotesFromGitLab = (release) =>
  truncate(normalizeStoreText(release?.description));

export const releaseNotesFromCodeberg = (release) =>
  truncate(normalizeStoreText(release?.body));

export const releaseNotesFromFdroid = (localized) =>
  truncate(normalizeStoreText(localized?.whatsNew));