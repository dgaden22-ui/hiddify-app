package com.hiddify.hiddify

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * DgadenVPN: keeps the reason the app last died, so it can be shown in the logs page.
 *
 * The VPN service runs in the app's process, so when it crashes the whole app closes
 * and the in-memory log goes with it. Two things survive and are written to
 * [REPORT_FILE] in filesDir, which the Dart side reads and logs on the next start:
 * the stack trace of an uncaught Kotlin/Java exception, and (Android 11+) the exit
 * reason Android itself records: crash, native crash, low memory, killed, ANR.
 */
object CrashRecorder {
    const val REPORT_FILE = "dgaden_last_exit.txt"
    private const val TAG = "CrashRecorder"
    private const val PREFS = "dgaden_crash_recorder"
    private const val KEY_LAST_EXIT = "last_reported_exit_ts"

    private val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    fun install(context: Context) {
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                append(
                    app,
                    "uncaught exception in thread '${thread.name}' at ${time.format(Date())}:\n" +
                        Log.getStackTraceString(error).take(6000),
                )
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
        try {
            recordExitReasons(app)
        } catch (e: Throwable) {
            Log.w(TAG, "could not read exit reasons", e)
        }
    }

    private fun recordExitReasons(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val am = context.getSystemService(ActivityManager::class.java) ?: return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lastReported = prefs.getLong(KEY_LAST_EXIT, 0L)
        val exits = am.getHistoricalProcessExitReasons(context.packageName, 0, 5)
            .filter { it.timestamp > lastReported }
            .sortedBy { it.timestamp }
        if (exits.isEmpty()) return
        val text = exits.joinToString("\n") { describe(it) }
        append(context, text)
        prefs.edit().putLong(KEY_LAST_EXIT, exits.maxOf { it.timestamp }).apply()
    }

    private fun describe(e: ApplicationExitInfo): String {
        val reason = when (e.reason) {
            ApplicationExitInfo.REASON_ANR -> "ANR (app not responding)"
            ApplicationExitInfo.REASON_CRASH -> "CRASH (Java/Kotlin exception)"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE (native code, e.g. the VPN core)"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF (the app closed itself)"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY (killed: not enough memory)"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED (killed by signal ${e.status})"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            else -> "reason ${e.reason}"
        }
        return "app exit at ${time.format(Date(e.timestamp))}: $reason; " +
            "process=${e.processName}, status=${e.status}, importance=${e.importance}, " +
            "pss=${e.pss / 1024}MB, rss=${e.rss / 1024}MB, android=${Build.VERSION.SDK_INT}, " +
            "abi=${Build.SUPPORTED_ABIS.joinToString("/")}" +
            (e.description?.let { ", description: $it" } ?: "") +
            nativeTombstone(e)
    }

    /**
     * Android 12+ keeps the tombstone of a native crash: the abort message, the signal
     * and the backtrace with library and function names. It comes as protobuf; the
     * readable strings in it are enough to tell what aborted (e.g. fdsan, the Go core).
     */
    private fun nativeTombstone(e: ApplicationExitInfo): String {
        if (e.reason != ApplicationExitInfo.REASON_CRASH_NATIVE || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return ""
        }
        return try {
            val bytes = e.traceInputStream?.use { it.readBytes() } ?: return "; no tombstone"
            val strings = Regex("[\\x20-\\x7E]{6,}")
                .findAll(String(bytes, Charsets.ISO_8859_1))
                .map { it.value.trim() }
                .filter { it.isNotEmpty() }
                .distinct()
                .take(80)
                .joinToString(" | ")
            "; tombstone: " + strings.take(3500)
        } catch (t: Throwable) {
            "; tombstone unreadable: $t"
        }
    }

    private fun append(context: Context, text: String) {
        File(context.filesDir, REPORT_FILE).appendText(text + "\n")
    }
}
