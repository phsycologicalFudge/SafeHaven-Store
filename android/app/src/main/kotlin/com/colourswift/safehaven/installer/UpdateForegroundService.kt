package com.colourswift.safehaven

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import android.content.pm.PackageInstaller
import org.json.JSONArray
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger

class UpdateForegroundService : Service() {
    private val NOTIFICATION_ID = 888
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeFiles = mutableListOf<File>()
    private val activePackages = Collections.synchronizedSet(mutableSetOf<String>())

    companion object {
        const val PROGRESS_CHANNEL_ID = "safehaven_update_channel"
        const val RESULT_CHANNEL_ID = "safehaven_manual_update"
        const val SUMMARY_NOTIF_ID = 890

        private val pendingInstalls = AtomicInteger(0)
        private val failedCount = AtomicInteger(0)

        fun reset(total: Int) {
            pendingInstalls.set(total)
            failedCount.set(0)
        }

        fun onInstallResult(context: Context, success: Boolean) {
            if (!success) failedCount.incrementAndGet()
            if (pendingInstalls.decrementAndGet() <= 0) {
                val failed = failedCount.getAndSet(0)
                if (failed > 0) showFailureSummary(context, failed)
            }
        }

        private fun showFailureSummary(context: Context, count: Int) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notif = NotificationCompat.Builder(context, RESULT_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification_safehaven)
                .setContentTitle("$count update${if (count != 1) "s" else ""} failed")
                .setContentText("Open SafeHaven for details")
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()
            manager.notify(SUMMARY_NOTIF_ID, notif)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        abandonStaleSessions()
        startForeground(NOTIFICATION_ID, buildProgressNotification(0, 0))

        val updatesJson = intent?.getStringExtra("updates_json")
        if (updatesJson.isNullOrEmpty()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val updates = parseUpdatesJson(updatesJson)
        if (updates.isEmpty()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val pending = updates.filter { (packageName, _) -> activePackages.add(packageName) }
        if (pending.isEmpty()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        reset(pending.size)

        val total = pending.size
        val completed = AtomicInteger(0)
        updateProgressNotification(0, total)

        scope.launch {
            pending.map { (packageName, downloadUrl) ->
                async {
                    processUpdate(packageName, downloadUrl)
                    val done = completed.incrementAndGet()
                    withContext(Dispatchers.Main) {
                        updateProgressNotification(done, total)
                    }
                }
            }.awaitAll()
            stopSelf(startId)
        }

        return START_NOT_STICKY
    }

    private fun buildProgressNotification(done: Int, total: Int): Notification {
        val text = when {
            total == 0 -> "Preparing updates..."
            done < total -> "Updating apps ($done / $total)..."
            else -> "All updates complete"
        }
        val builder = NotificationCompat.Builder(this, PROGRESS_CHANNEL_ID)
            .setContentTitle("SafeHaven Updates")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification_safehaven)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(done < total || total == 0)
        if (total > 0) builder.setProgress(total, done, false)
        return builder.build()
    }

    private fun abandonStaleSessions() {
        val packageInstaller = packageManager.packageInstaller
        packageInstaller.mySessions.forEach { sessionInfo ->
            try {
                packageInstaller.openSession(sessionInfo.sessionId).abandon()
            } catch (_: Exception) {}
        }
    }

    private fun updateProgressNotification(done: Int, total: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildProgressNotification(done, total))
    }

    private fun parseUpdatesJson(json: String): List<Pair<String, String>> {
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.getJSONObject(i)
                val packageName = obj.optString("packageName").takeIf { it.isNotBlank() }
                val downloadUrl = obj.optString("downloadUrl").takeIf { it.isNotBlank() }
                if (packageName != null && downloadUrl != null) packageName to downloadUrl else null
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private suspend fun processUpdate(packageName: String, downloadUrl: String) {
        val file = File(cacheDir, "${packageName}_update_${System.currentTimeMillis()}.apk")
        synchronized(activeFiles) { activeFiles.add(file) }
        try {
            val connection = URL(downloadUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 60_000
            connection.inputStream.use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            installApk(packageName, file)
        } catch (e: Exception) {
            android.util.Log.e("UpdateForegroundService", "Update failed: pkg=$packageName msg=${e.message}")
            onInstallResult(this, false)
        } finally {
            file.delete()
            synchronized(activeFiles) { activeFiles.remove(file) }
            activePackages.remove(packageName)
        }
    }

    private fun installApk(packageName: String, file: File) {
        val packageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setInstallerPackageName(this.packageName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }

        val sessionId = packageInstaller.createSession(params)
        val session = packageInstaller.openSession(sessionId)

        try {
            file.inputStream().use { input ->
                session.openWrite("package_install_session", 0, file.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            val intent = Intent(this, UpdateReceiver::class.java).apply {
                putExtra(PackageInstaller.EXTRA_PACKAGE_NAME, packageName)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                sessionId,
                intent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            )

            session.commit(pendingIntent.intentSender)
        } finally {
            session.close()
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(PROGRESS_CHANNEL_ID, "SafeHaven Update Progress", NotificationManager.IMPORTANCE_LOW)
            )
            manager.createNotificationChannel(
                NotificationChannel(RESULT_CHANNEL_ID, "SafeHaven Update Results", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }

    override fun onDestroy() {
        scope.cancel()
        synchronized(activeFiles) {
            activeFiles.forEach { it.delete() }
            activeFiles.clear()
        }
        activePackages.clear()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}