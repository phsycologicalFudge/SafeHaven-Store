package com.colourswift.safehaven

import android.app.*
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

class UpdateForegroundService : Service() {
    private val CHANNEL_ID = "safehaven_update_channel"
    private val NOTIFICATION_ID = 888
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeFiles = mutableListOf<File>()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Updating Apps")
            .setContentText("SafeHaven is downloading updates in the background...")
            .setSmallIcon(R.drawable.ic_notification_safehaven)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)

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

        scope.launch {
            for ((packageName, downloadUrl) in updates) {
                processUpdate(packageName, downloadUrl)
            }
            stopSelf(startId)
        }

        return START_NOT_STICKY
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
            val intent = Intent(this, UpdateReceiver::class.java).apply {
                putExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
                putExtra(PackageInstaller.EXTRA_PACKAGE_NAME, packageName)
                putExtra(PackageInstaller.EXTRA_STATUS_MESSAGE, e.message)
            }
            sendBroadcast(intent)
        } finally {
            file.delete()
            synchronized(activeFiles) { activeFiles.remove(file) }
        }
    }

    private fun installApk(packageName: String, file: File) {
        val packageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)

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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Safe Haven Update Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        synchronized(activeFiles) {
            activeFiles.forEach { it.delete() }
            activeFiles.clear()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}