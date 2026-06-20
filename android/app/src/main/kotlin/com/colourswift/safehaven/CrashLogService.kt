package com.colourswift.safehaven

import android.content.Context
import android.content.Intent
import android.os.Environment
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object CrashLogService {
    private const val LOG_FILE = "safehaven_debug.log"
    private const val MAX_SIZE = 2L * 1024 * 1024
    private const val TRIM_TO = 1L * 1024 * 1024
    private const val PREFS_NAME = "safehaven_prefs"
    private const val KEY_DEBUG = "debug_logging_enabled"

    private var logFile: File? = null
    private var debugEnabled = false
    private val lock = Any()
    private var originalHandler: Thread.UncaughtExceptionHandler? = null
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    fun init(context: Context) {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        dir.mkdirs()
        logFile = File(dir, LOG_FILE)
        debugEnabled = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_DEBUG, false)
        installCrashHandler()
    }

    private fun installCrashHandler() {
        originalHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val trace = throwable.stackTraceToString()
                write("CRASH", "NativeCrash", "Uncaught on [${thread.name}]: $trace")
            } catch (_: Exception) {}
            originalHandler?.uncaughtException(thread, throwable)
        }
    }

    fun log(tag: String, level: String, msg: String) {
        if (!debugEnabled) return
        write(level, tag, msg)
    }

    fun crash(tag: String, msg: String) {
        write("CRASH", tag, msg)
    }

    fun setDebugEnabled(context: Context, enabled: Boolean) {
        debugEnabled = enabled
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DEBUG, enabled).apply()
    }

    fun isDebugEnabled(): Boolean = debugEnabled

    fun getLogContent(): String {
        return synchronized(lock) {
            logFile?.takeIf { it.exists() }?.readText() ?: ""
        }
    }

    fun clearLog() {
        synchronized(lock) {
            try {
                logFile?.takeIf { it.exists() }?.delete()
            } catch (_: Exception) {}
        }
    }

    fun shareLog(context: Context) {
        val file = logFile ?: return
        if (!file.exists()) return
        try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(Intent.createChooser(intent, "Share debug log").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (_: Exception) {}
    }

    fun hasLog(): Boolean {
        val file = logFile ?: return false
        return file.exists() && file.length() > 0
    }

    private fun write(level: String, tag: String, msg: String) {
        synchronized(lock) {
            val file = logFile ?: return
            try {
                rotate(file)
                val ts = dateFormat.format(Date())
                file.appendText("$ts [$level] [$tag] $msg\n")
            } catch (_: Exception) {}
        }
    }

    private fun rotate(file: File) {
        if (!file.exists() || file.length() < MAX_SIZE) return
        try {
            val bytes = file.readBytes()
            val start = (bytes.size - TRIM_TO.toInt()).coerceAtLeast(0)
            var pos = start
            while (pos < bytes.size && bytes[pos] != '\n'.code.toByte()) pos++
            if (pos < bytes.size) pos++
            file.writeBytes(bytes.copyOfRange(pos, bytes.size))
        } catch (_: Exception) {}
    }
}