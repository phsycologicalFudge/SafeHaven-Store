package com.colourswift.safehaven

import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object FullModeChecker {
    private const val BASE_URL = "https://api.colourswift.com"
    private const val PREFS = "safehaven_prefs"
    private const val TRIGGERED_KEY = "full_mode_triggered"

    fun isFullMode(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("update_mode", "light") == "full"

    fun run(context: Context) {
        val app = context.applicationContext
        if (!isFullMode(app)) return
        if (EngineNative.init(BASE_URL, app.filesDir.absolutePath) != 0) {
            CrashLogService.log("FullMode", "E", "engine init failed")
            return
        }
        unwrap(EngineNative.call("index.sync", """{"force":true}""")) ?: return

        val pm = app.packageManager
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val triggered = runCatching { JSONObject(prefs.getString(TRIGGERED_KEY, "{}") ?: "{}") }
            .getOrDefault(JSONObject())
        val args = JSONObject()
            .put("states", JSONObject(PackageStates.all(pm)))
            .put("triggered", triggered)
        val plan = unwrap(EngineNative.call("updates.plan", args.toString())) as? JSONArray ?: return

        val updates = JSONArray()
        for (i in 0 until plan.length()) {
            val entry = plan.getJSONObject(i)
            val packageName = entry.getString("packageName")
            if (PackageStates.isPlayStoreApp(pm, packageName)) continue
            updates.put(JSONObject().put("packageName", packageName).put("downloadUrl", entry.getString("downloadUrl")))
            triggered.put(packageName, entry.getLong("versionCode"))
        }
        if (updates.length() == 0) return

        val intent = Intent(app, UpdateForegroundService::class.java).putExtra("updates_json", updates.toString())
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(intent) else app.startService(intent)
            prefs.edit().putString(TRIGGERED_KEY, triggered.toString()).apply()
            CrashLogService.log("FullMode", "D", "started ${updates.length()} update(s)")
        } catch (e: Exception) {
            CrashLogService.log("FullMode", "E", "could not start updates: ${e.message}")
        }
    }

    private fun unwrap(envelope: String): Any? {
        val json = runCatching { JSONObject(envelope) }.getOrNull() ?: return null
        if (json.has("err")) {
            CrashLogService.log("FullMode", "E", json.optString("err"))
            return null
        }
        return json.opt("ok")
    }
}
