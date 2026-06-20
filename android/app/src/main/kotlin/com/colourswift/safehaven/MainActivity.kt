package com.colourswift.safehaven

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
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
    private val debugChannelName = "safehaven/debug"

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
            debugChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDebugLogging" -> {
                    result.success(CrashLogService.isDebugEnabled())
                }

                "setDebugLogging" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    CrashLogService.setDebugEnabled(this, enabled)
                    result.success(true)
                }

                "writeDebugLog" -> {
                    val tag = call.argument<String>("tag") ?: "Dart"
                    val level = call.argument<String>("level") ?: "E"
                    val msg = call.argument<String>("msg") ?: ""
                    CrashLogService.log(tag, level, msg)
                    result.success(true)
                }

                "writeCrashLog" -> {
                    val tag = call.argument<String>("tag") ?: "Dart"
                    val msg = call.argument<String>("msg") ?: ""
                    CrashLogService.crash(tag, msg)
                    result.success(true)
                }

                "hasLog" -> {
                    result.success(CrashLogService.hasLog())
                }

                "clearLog" -> {
                    CrashLogService.clearLog()
                    result.success(true)
                }

                "shareLog" -> {
                    CrashLogService.shareLog(this)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

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

                "getAllPackageStates" -> {
                    getAllPackageStates(result)
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
        CrashLogService.log("Installer", "D", "installApk called, sdk=${Build.VERSION.SDK_INT}")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            CrashLogService.log("Installer", "W", "install permission not granted, redirecting to settings")
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
            CrashLogService.log("Installer", "E", "APK file not found: $path")
            result.error("file_missing", "APK file does not exist", null)
            return
        }

        CrashLogService.log("Installer", "D", "APK exists, size=${file.length()}")

        val apkUri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: IllegalArgumentException) {
            CrashLogService.log("Installer", "E", "FileProvider failed: ${e.message}")
            result.error("fileprovider_error", e.message, null)
            return
        }

        CrashLogService.log("Installer", "D", "URI created, launching installer")

        fun buildIntent(pkg: String? = null): Intent =
            Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = apkUri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_RETURN_RESULT, false)
                if (pkg != null) setPackage(pkg)
            }

        fun resolveSystemInstaller(): String? {
            val probe = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = apkUri
                type = "application/vnd.android.package-archive"
            }
            return packageManager.queryIntentActivities(probe, 0)
                .firstOrNull {
                    it.activityInfo.applicationInfo.flags and
                            android.content.pm.ApplicationInfo.FLAG_SYSTEM != 0
                }
                ?.activityInfo?.packageName
        }

        try {
            startActivity(buildIntent())
            CrashLogService.log("Installer", "D", "startActivity succeeded")
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            CrashLogService.log("Installer", "W", "ActivityNotFoundException, trying system installer fallback")
            val systemPkg = resolveSystemInstaller()
            if (systemPkg != null) {
                try {
                    startActivity(buildIntent(systemPkg))
                    CrashLogService.log("Installer", "D", "fallback startActivity succeeded, pkg=$systemPkg")
                    result.success(true)
                } catch (e2: ActivityNotFoundException) {
                    CrashLogService.log("Installer", "E", "fallback failed: ${e2.message}")
                    result.error("installer_not_found", e2.message, null)
                }
            } else {
                CrashLogService.log("Installer", "E", "no system installer found")
                result.error("installer_not_found", e.message, null)
            }
        } catch (e: Exception) {
            CrashLogService.log("Installer", "E", "${e.javaClass.simpleName}: ${e.message}")
            result.error("install_failed", e.message, null)
        }
    }

    private fun getAllPackageStates(result: MethodChannel.Result) {
        try {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }

            val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getInstalledPackages(PackageManager.PackageInfoFlags.of(flags.toLong()))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstalledPackages(flags)
            }

            val map = mutableMapOf<String, Map<String, Any?>>()
            for (info in packages) {
                val pkgName = info.packageName
                val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    info.versionCode.toLong()
                }
                val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        packageManager.getInstallSourceInfo(pkgName).installingPackageName
                    } catch (_: Exception) {
                        null
                    }
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getInstallerPackageName(pkgName)
                }
                map[pkgName] = mapOf(
                    "installed" to true,
                    "versionCode" to versionCode,
                    "versionName" to info.versionName,
                    "signingCertificateSha256" to getSigningCertificateSha256(info),
                    "installer" to installer
                )
            }
            result.success(map)
        } catch (e: Exception) {
            result.error("package_query_failed", e.message, null)
        }
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