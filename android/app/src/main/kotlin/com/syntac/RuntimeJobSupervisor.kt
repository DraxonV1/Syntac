// Owns persistent Arch runtime processes independently from Flutter Activity lifetime.

package com.syntac

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

class RuntimeJobSupervisor private constructor(private val context: Context) {
    data class StartRequest(
        val id: String,
        val command: String,
        val argv: List<String>,
        val workingDirectory: File,
        val environment: Map<String, String>,
        val ports: List<Int> = emptyList(),
        val restartCount: Int = 0,
    )

    private class Job(
        val record: JobRecord,
        val process: Process,
    ) {
        @Volatile var stopRequested = false
    }

    private data class JobRecord(
        val id: String,
        val command: String,
        val argv: List<String>,
        val workingDirectory: String,
        val environment: Map<String, String>,
        val stdoutPath: String,
        val stderrPath: String,
        val ports: List<Int>,
        val startedAt: Long,
        var state: String = "running",
        var finishedAt: Long? = null,
        var exitCode: Int? = null,
        var failureKind: String? = null,
        var restartCount: Int = 0,
        var omittedStdout: Long = 0,
        var omittedStderr: Long = 0,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("id", id)
            .put("command", command)
            .put("argv", JSONArray(argv))
            .put("workingDirectory", workingDirectory)
            .put("environment", JSONObject(environment))
            .put("stdoutPath", stdoutPath)
            .put("stderrPath", stderrPath)
            .put("ports", JSONArray(ports))
            .put("startedAt", startedAt)
            .put("state", state)
            .put("finishedAt", finishedAt)
            .put("exitCode", exitCode)
            .put("failureKind", failureKind)
            .put("restartCount", restartCount)
            .put("omittedStdout", omittedStdout)
            .put("omittedStderr", omittedStderr)

        companion object {
            fun fromJson(value: JSONObject): JobRecord {
                val argv = value.optJSONArray("argv")?.let { array ->
                    (0 until array.length()).map { array.optString(it) }
                } ?: emptyList()
                val environment = mutableMapOf<String, String>()
                value.optJSONObject("environment")?.let { json ->
                    json.keys().forEach { key -> environment[key] = json.optString(key) }
                }
                val ports = value.optJSONArray("ports")?.let { array ->
                    (0 until array.length()).mapNotNull { array.optInt(it, -1).takeIf { port -> port > 0 } }
                } ?: emptyList()
                return JobRecord(
                    id = value.optString("id"),
                    command = value.optString("command"),
                    argv = argv,
                    workingDirectory = value.optString("workingDirectory"),
                    environment = environment,
                    stdoutPath = value.optString("stdoutPath"),
                    stderrPath = value.optString("stderrPath"),
                    ports = ports,
                    startedAt = value.optLong("startedAt", System.currentTimeMillis()),
                    state = value.optString("state", "interrupted"),
                    finishedAt = value.optLong("finishedAt", 0L).takeIf { it > 0L },
                    exitCode = value.optInt("exitCode", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE },
                    failureKind = value.optString("failureKind").takeIf { it.isNotBlank() },
                    restartCount = value.optInt("restartCount", 0),
                    omittedStdout = value.optLong("omittedStdout", 0L),
                    omittedStderr = value.optLong("omittedStderr", 0L),
                )
            }
        }
    }

    private val runtimeDir = File(context.filesDir, "runtime")
    private val jobsDir = File(runtimeDir, "jobs")
    private val registryFile = File(runtimeDir, "runtime-jobs.json")
    private val jobs = ConcurrentHashMap<String, Job>()
    private val records = ConcurrentHashMap<String, JobRecord>()
    private val executor = Executors.newCachedThreadPool()
    private val lock = Any()
    @Volatile private var outputListener: ((Map<String, Any?>) -> Unit)? = null

    init {
        restoreRegistry()
    }

    fun bindOutput(listener: ((Map<String, Any?>) -> Unit)?) {
        outputListener = listener
    }

    fun hasActiveJobs(): Boolean = jobs.values.any { it.process.isAlive }

    fun start(request: StartRequest): Map<String, Any?> {
        if (request.id.isBlank() || request.command.isBlank()) {
            return failure("runtime_job_invalid", "id and command are required")
        }
        if (request.argv.isEmpty() || !request.workingDirectory.isDirectory) {
            return failure("runtime_job_invalid", "runtime command working directory is invalid")
        }
        synchronized(lock) {
            if (records.containsKey(request.id)) {
                return failure("runtime_job_duplicate", "A runtime job with this id already exists")
            }
            jobsDir.mkdirs()
            val stdoutPath = File(jobsDir, "${safeId(request.id)}.stdout.log").absolutePath
            val stderrPath = File(jobsDir, "${safeId(request.id)}.stderr.log").absolutePath
            val process = try {
                ProcessBuilder(request.argv)
                    .directory(request.workingDirectory)
                    .apply {
                        val env = environment()
                        env.clear()
                        env.putAll(request.environment)
                    }
                    .start()
            } catch (error: Throwable) {
                return failure("process_start_failed", safe(error))
            }
            File(stdoutPath).delete()
            File(stderrPath).delete()
            val record = JobRecord(
                id = request.id,
                command = request.command,
                argv = request.argv,
                workingDirectory = request.workingDirectory.absolutePath,
                environment = request.environment.filterKeys { key -> !key.contains("KEY") && !key.contains("TOKEN") && !key.contains("PASSWORD") && !key.contains("SECRET") },
                stdoutPath = stdoutPath,
                stderrPath = stderrPath,
                ports = request.ports,
                startedAt = System.currentTimeMillis(),
                restartCount = request.restartCount,
            )
            records[record.id] = record
            jobs[record.id] = Job(record, process)
            persistRegistry()
            startPump(record, process.inputStream, "stdout")
            startPump(record, process.errorStream, "stderr")
            executor.execute { awaitCompletion(record.id, process) }
            return snapshot(record).toMutableMap().apply {
                put("success", true)
                put("background", true)
                put("message", "Runtime job started")
            }
        }
    }

    fun status(id: String): Map<String, Any?>? = records[id]?.let(::snapshot)

    fun list(): List<Map<String, Any?>> = records.values
        .sortedByDescending { it.startedAt }
        .map(::snapshot)

    fun logs(id: String, maxCharacters: Int = 200_000): Map<String, Any?> {
        val record = records[id] ?: return failure("runtime_job_not_found", "Runtime job not found")
        val limit = maxCharacters.coerceIn(1, MAX_LOG_CHARACTERS)
        return snapshot(record) + mapOf(
            "success" to true,
            "jobId" to id,
            "stdout" to readTail(File(record.stdoutPath), limit),
            "stderr" to readTail(File(record.stderrPath), limit),
            "stdoutTruncated" to (record.omittedStdout > 0L),
            "stderrTruncated" to (record.omittedStderr > 0L),
        )
    }

    fun stop(id: String): Map<String, Any?> {
        val job = jobs[id]
        if (job == null) {
            val record = records[id] ?: return failure("runtime_job_not_found", "Runtime job not found")
            return snapshot(record).toMutableMap().apply {
                put("success", true)
                put("message", "Runtime job already exited")
            }
        }
        job.stopRequested = true
        killProcessTree(job.process)
        return snapshot(job.record).toMutableMap().apply {
            put("success", true)
            put("message", "Runtime job stop requested")
        }
    }

    fun stopAll(): List<Map<String, Any?>> = jobs.keys.toList().map { id -> stop(id) }

    fun restart(id: String): Map<String, Any?> {
        val previous = records[id] ?: return failure("runtime_job_not_found", "Runtime job not found")
        jobs[id]?.let {
            it.stopRequested = true
            killProcessTree(it.process)
            try { it.process.waitFor(2, TimeUnit.SECONDS) } catch (_: Throwable) {}
        }
        val newId = "${safeId(id)}-restart-${System.currentTimeMillis()}"
        return start(
            StartRequest(
                id = newId,
                command = previous.command,
                argv = previous.argv,
                workingDirectory = File(previous.workingDirectory),
                environment = previous.environment,
                ports = previous.ports,
                restartCount = previous.restartCount + 1,
            ),
        ).toMutableMap().apply {
            put("restartedFrom", id)
        }
    }


    private fun startPump(record: JobRecord, input: InputStream, stream: String) {
        executor.execute {
            input.use { source ->
                val buffer = ByteArray(4096)
                while (true) {
                    val count = try { source.read(buffer) } catch (_: Throwable) { break }
                    if (count <= 0) break
                    val text = String(buffer, 0, count, StandardCharsets.UTF_8)
                    val omitted = appendBounded(File(if (stream == "stdout") record.stdoutPath else record.stderrPath), text)
                    synchronized(lock) {
                        if (stream == "stdout") record.omittedStdout += omitted else record.omittedStderr += omitted
                        persistRegistry()
                    }
                    val event = mutableMapOf<String, Any?>(
                        "id" to record.id,
                        "stream" to stream,
                        "text" to text.take(MAX_EVENT_CHARS),
                        "${stream}Preview" to readTail(File(if (stream == "stdout") record.stdoutPath else record.stderrPath), 50_000),
                    )
                    outputListener?.let { listener ->
                        try { listener(event) } catch (_: Throwable) {}
                    }
                }
            }
        }
    }

    private fun awaitCompletion(id: String, process: Process) {
        val code = try { process.waitFor() } catch (_: Throwable) { -1 }
        synchronized(lock) {
            val job = jobs.remove(id)
            val record = records[id] ?: return
            record.finishedAt = System.currentTimeMillis()
            record.exitCode = code
            record.state = when {
                job?.stopRequested == true -> "cancelled"
                code == 0 -> "completed"
                else -> "failed"
            }
            record.failureKind = when {
                job?.stopRequested == true -> "cancelled"
                code == 0 -> null
                code >= 128 -> "runtime_signal"
                else -> "command_exit_error"
            }
            persistRegistry()
        }
    }

    private fun restoreRegistry() {
        synchronized(lock) {
            val array = try { JSONArray(registryFile.readText()) } catch (_: Throwable) { JSONArray() }
            for (index in 0 until array.length()) {
                val record = try { JobRecord.fromJson(array.getJSONObject(index)) } catch (_: Throwable) { continue }
                if (record.id.isBlank()) continue
                if (record.state == "running") {
                    record.state = "interrupted"
                    record.failureKind = "process_owner_restarted"
                    record.finishedAt = System.currentTimeMillis()
                    records[record.id] = record
                }
            }
            persistRegistry()
        }
    }

    private fun persistRegistry() {
        runtimeDir.mkdirs()
        val temp = File(registryFile.parentFile, "${registryFile.name}.tmp")
        try {
            val running = records.values
                .filter { it.state == "running" }
                .sortedBy { it.startedAt }
            FileOutputStream(temp).use { output ->
                output.write(
                    JSONArray(running.map(JobRecord::toJson)).toString(2)
                        .toByteArray(StandardCharsets.UTF_8),
                )
                output.flush()
                output.fd.sync()
            }
            if (!temp.renameTo(registryFile)) {
                temp.copyTo(registryFile, overwrite = true)
                temp.delete()
            }
        } catch (_: Throwable) {
            temp.delete()
        }
    }

    private fun snapshot(record: JobRecord): Map<String, Any?> {
        val finishedAt = record.finishedAt
        val durationEnd = finishedAt ?: System.currentTimeMillis()
        return mapOf(
            "jobId" to record.id,
            "command" to record.command,
            "state" to record.state,
            "running" to (record.state == "running"),
            "startedAt" to record.startedAt,
            "finishedAt" to finishedAt,
            "durationMs" to (durationEnd - record.startedAt).coerceAtLeast(0L),
            "exitCode" to record.exitCode,
            "jobSuccess" to (record.state == "completed" && record.exitCode == 0),
            "failureKind" to record.failureKind,
            "restartCount" to record.restartCount,
            "ports" to record.ports,
            "stdoutPreview" to readTail(File(record.stdoutPath), 50_000),
            "stderrPreview" to readTail(File(record.stderrPath), 50_000),
            "stdoutTruncated" to (record.omittedStdout > 0L),
            "stderrTruncated" to (record.omittedStderr > 0L),
            "omittedStdout" to record.omittedStdout,
            "omittedStderr" to record.omittedStderr,
        )
    }

    private fun readTail(file: File, maxCharacters: Int): String {
        if (!file.exists()) return ""
        return try {
            val text = file.readText(StandardCharsets.UTF_8)
            if (text.length <= maxCharacters) text else text.takeLast(maxCharacters)
        } catch (_: Throwable) {
            ""
        }
    }

    private fun appendBounded(file: File, text: String): Long {
        val clean = redact(text)
        return try {
            if (file.length() >= MAX_LOG_BYTES) return clean.toByteArray(StandardCharsets.UTF_8).size.toLong()
            val bytes = clean.toByteArray(StandardCharsets.UTF_8)
            val remaining = MAX_LOG_BYTES - file.length()
            val keep = bytes.size.coerceAtMost(remaining.toInt())
            FileOutputStream(file, true).use { it.write(bytes, 0, keep) }
            (bytes.size - keep).toLong()
        } catch (_: Throwable) {
            clean.toByteArray(StandardCharsets.UTF_8).size.toLong()
        }
    }

    private fun processPid(process: Process): Long = try {
        val field = process.javaClass.getDeclaredField("pid")
        field.isAccessible = true
        field.getLong(process)
    } catch (_: Throwable) {
        -1L
    }

    private fun killProcessTree(process: Process) {
        val pid = processPid(process)
        if (pid > 0L) {
            try { Runtime.getRuntime().exec(arrayOf("/system/bin/kill", "-TERM", "-$pid")) } catch (_: Throwable) {}
        }
        try { process.destroy() } catch (_: Throwable) {}
        try {
            if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly()
        } catch (_: Throwable) {
            try { process.destroyForcibly() } catch (_: Throwable) {}
        }
    }

    private fun safeId(id: String): String = id.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80).ifBlank { "job" }

    private fun redact(value: String): String = value.replace(
        Regex("(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)\\s*[=:]\\s*[^\\s]+"),
        "\$1=<redacted>",
    )

    private fun safe(error: Throwable): String = error.message ?: error.javaClass.simpleName

    private fun failure(kind: String, message: String): Map<String, Any?> = mapOf(
        "success" to false,
        "jobId" to "",
        "state" to "error",
        "failureKind" to kind,
        "stderr" to message,
        "exitCode" to -1,
        "background" to true,
    )

    companion object {
        private const val MAX_LOG_BYTES = 2_000_000L
        private const val MAX_LOG_CHARACTERS = 2_000_000
        private const val MAX_EVENT_CHARS = 32_000
        @Volatile private var instance: RuntimeJobSupervisor? = null

        fun get(context: Context): RuntimeJobSupervisor = instance ?: synchronized(this) {
            instance ?: RuntimeJobSupervisor(context.applicationContext).also { instance = it }
        }
    }
}
