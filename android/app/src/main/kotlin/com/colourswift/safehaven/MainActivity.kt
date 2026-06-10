package com.colourswift.safehaven

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val channelName = "safehaven/installer"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashScreenView ->
                splashScreenView.remove()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setForegroundService" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    getSharedPreferences("safehaven_prefs", MODE_PRIVATE)
                        .edit().putBoolean("foreground_service_enabled", enabled).apply()
                    val serviceIntent = Intent(this, StoreKeepAliveService::class.java)
                    if (enabled) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                    } else {
                        stopService(serviceIntent)
                    }
                    result.success(true)
                }

                "getForegroundService" -> {
                    val prefs = getSharedPreferences("safehaven_prefs", MODE_PRIVATE)
                    result.success(prefs.getBoolean("foreground_service_enabled", true))
                }

                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "APK path is missing", null)
                        return@setMethodCallHandler
                    }
                    val targetPackage = call.argument<String>("packageName")
                    if (!targetPackage.isNullOrBlank() && isPlayStoreApp(targetPackage)) {
                        result.error("play_store_app", "Cannot manually install a Play Store managed app", null)
                        return@setMethodCallHandler
                    }
                    installApk(path, result)
                }

                "startUnattendedUpdates" -> {
                    val updates = call.argument<List<Map<String, String>>>("updates")
                    if (updates.isNullOrEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val validUpdates = updates.filter { update ->
                        val packageName = update["packageName"]
                        packageName != null && !isPlayStoreApp(packageName)
                    }

                    if (validUpdates.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val updatesJson = org.json.JSONArray().apply {
                        validUpdates.forEach { update ->
                            put(org.json.JSONObject().apply {
                                put("packageName", update["packageName"])
                                put("downloadUrl", update["downloadUrl"])
                            })
                        }
                    }.toString()

                    val intent = Intent(this, UpdateForegroundService::class.java).apply {
                        putExtra("updates_json", updatesJson)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }

                "getPackageState" -> {
                    val targetPackage = call.argument<String>("packageName")
                    if (targetPackage.isNullOrBlank()) {
                        result.error("invalid_package", "Package name is missing", null)
                        return@setMethodCallHandler
                    }
                    getPackageState(targetPackage, result)
                }

                "openApp" -> {
                    val targetPackage = call.argument<String>("packageName")
                    if (targetPackage.isNullOrBlank()) {
                        result.error("invalid_package", "Package name is missing", null)
                        return@setMethodCallHandler
                    }
                    openApp(targetPackage, result)
                }

                "uninstallApp" -> {
                    val targetPackage = call.argument<String>("packageName")
                    if (targetPackage.isNullOrBlank()) {
                        result.error("invalid_package", "Package name is missing", null)
                        return@setMethodCallHandler
                    }
                    uninstallApp(targetPackage, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isPlayStoreApp(packageName: String): Boolean {
        return try {
            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
            installer == "com.android.vending"
        } catch (_: Exception) {
            false
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(settingsIntent)
            result.error("install_permission_required", "Install permission is required", null)
            return
        }

        val file = File(path)
        if (!file.exists()) {
            result.error("file_missing", "APK file does not exist", null)
            return
        }

        val apkUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        startActivity(installIntent)
        result.success(true)
    }

    private fun getPackageState(targetPackage: String, result: MethodChannel.Result) {
        try {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }

            val info = packageManager.getPackageInfo(targetPackage, flags)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }

            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    packageManager.getInstallSourceInfo(targetPackage).installingPackageName
                } catch (_: Exception) {
                    null
                }
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(targetPackage)
            }

            result.success(
                mapOf(
                    "installed" to true,
                    "versionCode" to versionCode,
                    "versionName" to info.versionName,
                    "signingCertificateSha256" to getSigningCertificateSha256(info),
                    "installer" to installer
                )
            )
        } catch (_: PackageManager.NameNotFoundException) {
            result.success(emptyPackageState())
        } catch (_: SecurityException) {
            result.success(emptyPackageState())
        }
    }

    private fun emptyPackageState(): Map<String, Any?> {
        return mapOf(
            "installed" to false,
            "versionCode" to 0L,
            "versionName" to null,
            "signingCertificateSha256" to null,
            "installer" to null
        )
    }

    private fun getSigningCertificateSha256(info: PackageInfo): String? {
        val signature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return null
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners.firstOrNull()
            } else {
                signingInfo.signingCertificateHistory.lastOrNull()
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.firstOrNull()
        } ?: return null

        val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun openApp(targetPackage: String, result: MethodChannel.Result) {
        val launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
        if (launchIntent == null) {
            result.error("app_not_found", "App cannot be opened", null)
            return
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(launchIntent)
        result.success(true)
    }

    private fun uninstallApp(targetPackage: String, result: MethodChannel.Result) {
        try {
            val uninstallIntent = Intent(Intent.ACTION_DELETE).apply {
                data = Uri.fromParts("package", targetPackage, null)
            }
            startActivity(uninstallIntent)
            result.success(true)
        } catch (e: Exception) {
            result.error("uninstall_failed", e.message, null)
        }
    }
}
