package com.hiddify.hiddify

import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * DgadenVPN: a short trace of how the VPN service was started.
 *
 * Starting the VPN goes through several steps on the Android side (notification
 * permission, VPN permission, the foreground service, the core). When one of them
 * fails or never answers, the app only sees "starting background core..." and the
 * reason stays in logcat, which a TV owner cannot read. Each step is appended to
 * [FILE] in filesDir; the Dart side shows the last lines in the logs page when
 * connecting fails.
 */
object ServiceTrace {
    const val FILE = "dgaden_service_trace.txt"
    private const val TAG = "ServiceTrace"
    private const val MAX_LINES = 60
    private val time = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    private val lock = Any()

    fun log(message: String) {
        Log.i(TAG, message)
        try {
            val dir = Application.application.filesDir
            val file = File(dir, FILE)
            synchronized(lock) {
                val lines = if (file.exists()) file.readLines().takeLast(MAX_LINES - 1) else emptyList()
                file.writeText((lines + "${time.format(Date())} $message").joinToString("\n") + "\n")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "could not write the service trace", e)
        }
    }
}
