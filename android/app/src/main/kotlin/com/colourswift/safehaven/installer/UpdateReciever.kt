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
    private val CHANNEL_ID = "safehaven_manual_update"

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val packageName = intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME) ?: ""
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)

                if (confirmIntent != null) {
                    try {
                        confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(confirmIntent)
                    } catch (_: Exception) {
                        val pIntent = PendingIntent.getActivity(
                            context,
                            packageName.hashCode(),
                            confirmIntent,
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                        )
                        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                            .setSmallIcon(R.drawable.ic_notification_safehaven)
                            .setContentTitle("Manual Update Required")
                            .setContentText("Tap to manually finish updating $packageName.")
                            .setPriority(NotificationCompat.PRIORITY_HIGH)
                            .setContentIntent(pIntent)
                            .setAutoCancel(true)
                            .build()
                        manager.notify(packageName.hashCode(), notification)
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification_safehaven)
                    .setContentTitle("Update Complete")
                    .setContentText("$packageName was updated successfully.")
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setAutoCancel(true)
                    .build()

                manager.notify(packageName.hashCode(), notification)
            }
            else -> {
                val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification_safehaven)
                    .setContentTitle("Update Failed")
                    .setContentText("Failed to update $packageName.")
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setAutoCancel(true)
                    .build()

                manager.notify(packageName.hashCode(), notification)
            }
        }
    }
}