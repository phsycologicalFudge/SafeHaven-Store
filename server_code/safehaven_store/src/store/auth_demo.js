// SPDX-FileCopyrightText: 2026 ColourSwift Ltd.
// SPDX-License-Identifier: AGPL-3.0-only

import { getBearerToken } from "./auth.js";

export const demoAuth = {
  async getUser(request, env) {
    // This demo adapter uses static bearer tokens from wrangler.jsonc.
    // Replace this file with your own login provider for production.
    const token = getBearerToken(request);
    if (!token) return null;

    const devToken = (env.DEMO_DEV_TOKEN || "").trim();
    const adminToken = (env.DEMO_ADMIN_TOKEN || "").trim();

    // Admins can approve, reject, remove, and suspend apps.
    if (adminToken && token === adminToken) {
      return {
        id: "demo-admin",
        email: "admin@example.com",
        developerEnabled: true,
        admin: true,
      };
    }

    // Developers can register apps, verify repos, and submit APKs.
    if (devToken && token === devToken) {
      return {
        id: "demo-dev",
        email: "dev@example.com",
        developerEnabled: true,
        admin: false,
      };
    }

    return null;
  },
};
