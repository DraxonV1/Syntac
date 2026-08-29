
package com.syntac

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

object TermuxBridge {
    private val pendingResults = ConcurrentHashMap<String, MethodChannel.Result>()
    private val requestCodes = ConcurrentHashMap<String, Int>()
    private val nextRequestCode = AtomicInteger(1000)
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile var lastBridgeResult: Map<String, Any?> = emptyMap()
        private set
    @Volatile var lastLaunchState: String = "none"
        private set
    @Volatile var lastRuntimeErrorCategory: String = "none"
        private set

    fun register(id: String, result: MethodChannel.Result) {
        pendingResults[id] = result
    }

    fun pendingIntent(context: Context, id: String, intent: Intent): PendingIntent {
        val requestCode = nextRequestCode.incrementAndGet()
        requestCodes[id] = requestCode
        val flags = PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getService(context, requestCode, intent, flags)
    }

    fun complete(id: String, bundle: Bundle?) {
        val payload = if (bundle == null) {
            mapOf(
                "stdout" to "",
                "stderr" to "Missing Termux result bundle",
                "exitCode" to -1,
                "timedOut" to false,
                "cancelled" to false,
                "failureKind" to "CallbackFailed",
            )
        } else {
            val exitCode = bundle.getInt("exitCode", -1)
            val rawStdout = bundle.getString("stdout", "")
            val rawStderr = bundle.getString("stderr", "")
            val stdout = boundedRuntimeOutput(rawStdout)
            val stderr = boundedRuntimeOutput(rawStderr)
            mapOf(
                "stdout" to stdout,
                "stderr" to stderr,
                "exitCode" to exitCode,
                "err" to bundle.getInt("err", -1),
                "errmsg" to boundedRuntimeOutput(bundle.getString("errmsg", "")),
                "stdoutOriginalLength" to rawStdout.length,
                "stderrOriginalLength" to rawStderr.length,
                "stdoutTruncated" to (stdout != rawStdout),
                "stderrTruncated" to (stderr != rawStderr),
                "timedOut" to (exitCode == 124),
                "cancelled" to false
            )
        }
        finish(id, payload)
    }

    fun markLaunch(state: String) {
        lastLaunchState = state
        if (state == "started") lastRuntimeErrorCategory = "none"
    }

    fun cancel(id: String) {
        finish(id, mapOf("stdout" to "", "stderr" to "Command cancelled by app", "exitCode" to -1, "failureKind" to "Cancelled", "timedOut" to false, "cancelled" to true))
    }

    fun fail(id: String, message: String, failureKind: String = "LaunchFailed") {
        finish(id, mapOf("stdout" to "", "stderr" to message, "exitCode" to -1, "failureKind" to failureKind, "timedOut" to false, "cancelled" to false))
    }

    private fun finish(id: String, payload: Map<String, Any?>) {
        requestCodes.remove(id)
        lastBridgeResult = payload
        lastLaunchState = if (payload["failureKind"] == null) "completed" else "failed"
        lastRuntimeErrorCategory = when (payload["failureKind"]) {
            "TermuxBackgroundRestricted" -> "termux_background_restricted"
            "CallbackFailed" -> "runtime_callback_failed"
            "LaunchFailed" -> "runtime_launch_failed"
            "Cancelled" -> "cancelled"
            else -> if ((payload["exitCode"] as? Int ?: -1) == 0) "none" else "command_exit_error"
        }
        val result = pendingResults.remove(id) ?: return
        mainHandler.post { result.success(payload) }
    }
}
