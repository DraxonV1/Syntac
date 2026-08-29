package com.syntac

import java.io.InputStream
import kotlin.math.max
import kotlin.math.min

/** Normalized runtime command result shared by local runtime manager paths. */
data class LocalRunResult(
    val command: String = "none",
    val stdout: String = "",
    val stderr: String = "",
    val exitCode: Int = -1,
    val durationMs: Long = 0,
    val timedOut: Boolean = false,
    val cancelled: Boolean = false,
    val errorCategory: String? = null,
    val runtimeSignal: String? = null,
    val guestExitCode: Int? = null,
) {
    val success: Boolean = exitCode == 0 && !timedOut && !cancelled

    fun toMap(): Map<String, Any?> = mapOf(
        "stdout" to stdout,
        "stderr" to stderr,
        "exitCode" to exitCode,
        "durationMs" to durationMs,
        "timedOut" to timedOut,
        "cancelled" to cancelled,
        "success" to success,
        "failureKind" to errorCategory,
        "runtimeSignal" to runtimeSignal,
        "guestExitCode" to guestExitCode,
    )

    companion object {
        fun fromMap(map: Map<String, Any?>): LocalRunResult = LocalRunResult(
            stdout = map["stdout"]?.toString().orEmpty(),
            stderr = map["stderr"]?.toString().orEmpty(),
            exitCode = (map["exitCode"] as? Number)?.toInt() ?: -1,
            durationMs = (map["durationMs"] as? Number)?.toLong() ?: 0,
            timedOut = map["timedOut"] == true,
            cancelled = map["cancelled"] == true,
            errorCategory = map["failureKind"]?.toString(),
            runtimeSignal = map["runtimeSignal"]?.toString(),
            guestExitCode = (map["guestExitCode"] as? Number)?.toInt(),
        )
    }
}

private const val MAX_RUNTIME_STREAM_CHARS = 64_000

fun boundedRuntimeOutput(value: String): String {
    if (value.length <= MAX_RUNTIME_STREAM_CHARS) return value
    val marker = "\n[output truncated ${value.length - MAX_RUNTIME_STREAM_CHARS} characters]"
    val keep = (MAX_RUNTIME_STREAM_CHARS - marker.length).coerceAtLeast(0)
    return value.take(keep) + marker
}

private fun composeRuntimeOutput(value: String, omitted: Long, pending: Boolean): String {
    val marker = buildString {
        if (omitted > 0) append("\n[output truncated $omitted characters]")
        if (pending) append("\n[output still draining]")
    }
    if (marker.isEmpty()) return value
    val keep = (MAX_RUNTIME_STREAM_CHARS - marker.length).coerceAtLeast(0)
    return value.take(keep) + marker
}

fun readAsync(input: InputStream, onChunk: ((String, String, Boolean, Long) -> Unit)? = null): () -> String {
    val lock = Object()
    val buffer = StringBuilder(MAX_RUNTIME_STREAM_CHARS)
    var omitted = 0L
    var done = false
    val thread = Thread {
        input.bufferedReader().use { reader ->
            val chunk = CharArray(4096)
            while (true) {
                val read = reader.read(chunk)
                if (read < 0) break
                val text = String(chunk, 0, read)
                var snapshot = ""
                var truncated = false
                var originalLength = 0L
                synchronized(lock) {
                    val remaining = MAX_RUNTIME_STREAM_CHARS - buffer.length
                    if (remaining > 0) {
                        val keep = min(read, remaining)
                        buffer.append(chunk, 0, keep)
                        omitted += max(0, read - keep).toLong()
                    } else {
                        omitted += read.toLong()
                    }
                    originalLength = buffer.length + omitted
                    truncated = omitted > 0
                    snapshot = composeRuntimeOutput(buffer.toString(), omitted, false)
                }
                onChunk?.invoke(text, snapshot, truncated, originalLength)
            }
        }
        synchronized(lock) { done = true }
    }
    thread.start()
    return {
        thread.join(2000)
        synchronized(lock) {
            composeRuntimeOutput(buffer.toString(), omitted, !done)
        }
    }
}

fun runFailure(kind: String, message: String): Map<String, Any?> = LocalRunResult(
    stderr = message,
    errorCategory = kind,
).toMap()
