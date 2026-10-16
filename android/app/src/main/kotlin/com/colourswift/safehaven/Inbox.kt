package com.colourswift.safehaven

import android.content.Context
import org.json.JSONObject
import java.io.File

object Inbox {
    private const val FILE_NAME = "inbox_native.jsonl"

    fun post(context: Context, kind: String, packageName: String) {
        val pm = context.packageManager
        val appName = runCatching {
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        }.getOrDefault(packageName)
        val version = runCatching { pm.getPackageInfo(packageName, 0).versionName }.getOrNull()
        val at = System.currentTimeMillis()
        val line = JSONObject()
            .put("id", "$at|$kind|$packageName")
            .put("kind", kind)
            .put("packageName", packageName)
            .put("appName", appName)
            .put("detail", version ?: "")
            .put("at", at)
            .toString()
        synchronized(this) {
            runCatching { File(context.filesDir, FILE_NAME).appendText(line + "\n") }
        }
    }
}
