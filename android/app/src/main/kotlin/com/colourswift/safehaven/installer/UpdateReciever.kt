package com.colourswift.safehaven

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import androidx.core.app.NotificationCompat
import com.colourswift.safehaven.R

class UpdateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val packageName = intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME) ?: ""

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                val appName = try {
                    val info = context.packageManager.getApplicationInfo(packageName, 0)
                    context.packageManager.getApplicationLabel(info).toString()
                } catch (_: Exception) {
                    packageName
                }
                val pIntent = PendingIntent.getActivity(
                    context,
                    packageName.hashCode(),
                    confirmIntent,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
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
                UpdateForegroundService.onInstallResult(context, true)
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "no message"
                val statusCode = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
                android.util.Log.e("UpdateReceiver", "Install failed: pkg=$packageName status=$statusCode msg=$message")
                UpdateForegroundService.onInstallResult(context, false)
            }
        }
    }
}