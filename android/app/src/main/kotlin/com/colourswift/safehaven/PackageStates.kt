package com.colourswift.safehaven

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

object PackageStates {
    private val signingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        @Suppress("DEPRECATION")
        PackageManager.GET_SIGNATURES
    }

    val empty: Map<String, Any?> = mapOf(
        "installed" to false,
        "versionCode" to 0L,
        "versionName" to null,
        "signingCertificateSha256" to null,
        "installer" to null
    )

    fun all(pm: PackageManager): Map<String, Map<String, Any?>> {
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(signingFlags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(signingFlags)
        }
        return packages.associate { it.packageName to state(pm, it) }
    }

    fun single(pm: PackageManager, packageName: String): Map<String, Any?> {
        return try {
            state(pm, pm.getPackageInfo(packageName, signingFlags))
        } catch (_: PackageManager.NameNotFoundException) {
            empty
        } catch (_: SecurityException) {
            empty
        }
    }

    fun installer(pm: PackageManager, packageName: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(packageName)
            }
        } catch (_: Exception) {
            null
        }
    }

    fun isPlayStoreApp(pm: PackageManager, packageName: String): Boolean =
        installer(pm, packageName) == "com.android.vending"

    private fun state(pm: PackageManager, info: PackageInfo): Map<String, Any?> {
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "installed" to true,
            "versionCode" to versionCode,
            "versionName" to info.versionName,
            "signingCertificateSha256" to signingSha256(info),
            "installer" to installer(pm, info.packageName)
        )
    }

    private fun signingSha256(info: PackageInfo): String? {
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
}
