package com.colourswift.safehaven

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import com.colourswift.safehaven.R

class UpdateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val packageName = intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME) ?: ""

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                }

                if (confirmIntent == null) {
                    CrashLogService.log("UpdateReceiver", "W", "PENDING_USER_ACTION with no confirm intent: pkg=$packageName")
                    UpdateForegroundService.onInstallResult(context, false, packageName)
                    return
                }

                val appName = try {
                    val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        context.packageManager.getApplicationInfo(
                            packageName,
                            PackageManager.ApplicationInfoFlags.of(0)
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        context.packageManager.getApplicationInfo(packageName, 0)
                    }
                    context.packageManager.getApplicationLabel(info).toString()
                } catch (_: Exception) {
                    packageName
                }

                val pIntent = PendingIntent.getActivity(
                    context,
                    packageName.hashCode(),
                    confirmIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                val notification = NotificationCompat.Builder(context, UpdateForegroundService.RESULT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification_safehaven)
                    .setContentTitle("Tap to finish update")
                    .setContentText(appName)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setContentIntent(pIntent)
                    .setAutoCancel(true)
                    .build()
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(packageName.hashCode(), notification)
            }
            PackageInstaller.STATUS_SUCCESS -> {
                UpdateForegroundService.onInstallResult(context, true, packageName)
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "no message"
                val statusCode = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
                CrashLogService.log("UpdateReceiver", "E", "Install failed: pkg=$packageName status=$statusCode msg=$message")
                UpdateForegroundService.onInstallResult(context, false, packageName)
            }
        }
    }
}