// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { normalizeStoreText } from "./store_helpers.js";

export const WHATS_NEW_MAX_CHARS = 4000;

export const capWhatsNew = (text) => {
  if (!text) return null;
  if (text.length <= WHATS_NEW_MAX_CHARS) return text;
  return text.slice(0, WHATS_NEW_MAX_CHARS).trim() + "…";
};

export const releaseNotesFromGitHub = (release) =>
  capWhatsNew(normalizeStoreText(release?.body));

export const releaseNotesFromGitLab = (release) =>
  capWhatsNew(normalizeStoreText(release?.description));

export const releaseNotesFromCodeberg = (release) =>
  capWhatsNew(normalizeStoreText(release?.body));

export const releaseNotesFromFdroid = (localized) =>
  capWhatsNew(normalizeStoreText(localized?.whatsNew));