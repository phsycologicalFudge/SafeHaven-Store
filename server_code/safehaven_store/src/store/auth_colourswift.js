import { getUserByToken } from "../db.js";
import { getBearerToken, normalizeStoreUser } from "./auth.js";

export const colourSwiftAuth = {
  async getUser(request, env) {
    const token = getBearerToken(request);
    if (!token) return null;

    const user = await getUserByToken(env, token);
    if (!user) return null;

    const adminEmail = (env.ADMIN_EMAIL || "").toString().trim().toLowerCase();
    const adminIds = (env.ADMIN_USER_IDS || "").split(",").map((s) => s.trim()).filter(Boolean);

    let developerEnabled = user.developerEnabled === true || Number(user.developer_enabled || 0) === 1;

    if (!developerEnabled) {
      const row = await env.api_control_db
        .prepare("SELECT developer_enabled FROM users WHERE id = ?1")
        .bind(user.id)
        .first();

      developerEnabled = Number(row?.developer_enabled || 0) === 1;
    }

    return normalizeStoreUser({
      id: user.id,
      email: user.email || "",
      developerEnabled,
      admin: adminIds.includes(user.id) || (adminEmail && (user.email || "").toString().trim().toLowerCase() === adminEmail),
    });
  },
};
