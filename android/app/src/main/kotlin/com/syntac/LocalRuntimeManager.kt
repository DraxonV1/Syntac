package com.syntac

import android.app.Activity
import android.os.Build
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min
import org.json.JSONArray
import org.json.JSONObject

class LocalRuntimeManager(
    private val activity: Activity,
    private val emitCommandOutput: (Map<String, Any?>) -> Unit = {},
) {
    private val active = ConcurrentHashMap<String, Process>()
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private var last = LocalRunResult()
    @Volatile private var installRunning = false

    private val runtimeDir = File(activity.filesDir, "runtime")
    private val rootfsDir = File(runtimeDir, "arch")
    private val installingDir = File(runtimeDir, "arch.installing")
    private val cacheDir = File(runtimeDir, "cache")
    private val tmpDir = File(runtimeDir, "tmp")
    private val metadataFile = File(runtimeDir, "local-runtime.json")
    private val nativeDir = File(activity.applicationInfo.nativeLibraryDir)
    private val launcher = File(nativeDir, "libsyntac_proot.so")
    private val minFreeAfterInstallBytes = 512L * 1024L * 1024L
    private val minFreeBeforePackageBytes = 512L * 1024L * 1024L
    private val maxRuntimeStreamChars = 64_000

    fun status(): Map<String, Any?> {
        val current = metadata()?.takeIf { metadataBelongsToCurrentRuntime(it) }
        val installed = runtimeMetadataMatches(current) && current?.optBoolean("ready") == true && rootfsDir.exists()
        val state = when {
            !abiSupported() -> "unavailable"
            missingRuntimeFiles().isNotEmpty() -> "configurationRequired"
            installRunning -> "installing"
            installed -> "ready"
            current?.optBoolean("installInProgress") == true -> "installing"
            current?.optString("state") == "error" -> "error"
            rootfsDir.exists() -> "notInstalled"
            else -> "notInstalled"
        }
        val message = when (state) {
            "unavailable" -> "Android ABI ${selectedAbi()} is not supported."
            "configurationRequired" -> "ARCH Linux Runtime files are missing."
            "installing" -> current?.optString("message", "Installing ARCH Linux Runtime") ?: "Installing ARCH Linux Runtime"
            "ready" -> "ARCH Linux Runtime is ready."
            "error" -> current?.optString("message", "ARCH Linux Runtime needs reinstall or reset.") ?: "ARCH Linux Runtime needs reinstall or reset."
            else -> "ARCH Linux Runtime is not installed."
        }
        return mapOf("state" to state, "message" to message, "details" to lightweightDetails(state, current))
    }

    fun install(result: MethodChannel.Result) {
        if (installRunning) {
            result.success(mapOf("state" to "installing", "message" to "ARCH Linux Runtime install is already running.", "details" to lightweightDetails("installing", metadata())))
            return
        }
        installRunning = true
        Thread {
            val output = try {
                installBlocking()
            } catch (error: Throwable) {
                finishError("install_failed: ${safe(error)}")
            } finally {
                installRunning = false
            }
            activity.runOnUiThread { result.success(output) }
        }.start()
    }

    fun retrySelfTest(result: MethodChannel.Result) {
        Thread {
            val output = runSelfTestOnly()
            activity.runOnUiThread { result.success(output) }
        }.start()
    }
    fun remove(): Map<String, Any?> {
        active.forEach { (id, process) ->
            cancelled.add(id)
            process.destroyForcibly()
        }
        active.clear()
        runtimeDir.deleteRecursively()
        last = LocalRunResult()
        return mapOf("state" to "notInstalled", "message" to "ARCH Linux Runtime removed.", "details" to lightweightDetails("notInstalled", null))
    }

    fun runCommand(args: Map<*, *>?, result: MethodChannel.Result) {
        val id = args?.get("id")?.toString().orEmpty()
        val command = args?.get("command")?.toString().orEmpty()
        val workDir = args?.get("workingDirectory")?.toString().orEmpty()
        val timeout = (args?.get("timeoutSeconds") as? Number)?.toLong()?.takeIf { it > 0 } ?: 120L
        val activeProject = parseProject(args?.get("activeProject") as? Map<*, *>) ?: BoundProject(File(workDir.ifBlank { runtimeDir.absolutePath }), mountNameForPath(workDir.ifBlank { "project" }))
        val projects = parseProjects(args?.get("availableProjects")).ifEmpty { listOf(activeProject) }
        Thread {
            val output = try {
                val validation = validateRootfs(rootfsDir)
                when {
                    id.isBlank() || command.isBlank() -> runFailure("runtime_exec_failed", "id and command are required")
                    !runtimeMetadataMatches(metadata()) || !validation.ready -> runFailure("local_runtime_not_installed", "ARCH Linux Runtime is not installed. Arch rootfs validation: ${validation.summary}")
                    else -> execute(id, command, activeProject, projects, timeout)
                }
            } catch (error: Exception) {
                runFailure("runtime_exec_failed", safe(error))
            }
            activity.runOnUiThread { result.success(output) }
        }.start()
    }

    fun cancel(id: String) {
        cancelled.add(id)
        active.remove(id)?.destroyForcibly()
    }

    private fun runFailure(kind: String, message: String): Map<String, Any?> = LocalRunResult(
        stderr = message,
        errorCategory = kind,
    ).toMap()

    private fun readAsync(input: InputStream, onChunk: ((String, String, Boolean, Long) -> Unit)? = null): () -> String {
        val lock = Object()
        val buffer = StringBuilder(maxRuntimeStreamChars)
        var omitted = 0L
        var done = false
        val thread = Thread {
            input.bufferedReader().use { reader ->
                val chunk = CharArray(4096)
                while (true) {
                    val read = reader.read(chunk)
                    if (read < 0) break
                    val text = String(chunk, 0, read)
                    var snapshot: String
                    var truncated: Boolean
                    var originalLength: Long
                    synchronized(lock) {
                        val remaining = maxRuntimeStreamChars - buffer.length
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
            synchronized(lock) { composeRuntimeOutput(buffer.toString(), omitted, !done) }
        }
    }

    private fun composeRuntimeOutput(value: String, omitted: Long, pending: Boolean): String {
        val marker = buildString {
            if (omitted > 0) append("\n[output truncated $omitted characters]")
            if (pending) append("\n[output still draining]")
        }
        if (marker.isEmpty()) return value
        val keep = (maxRuntimeStreamChars - marker.length).coerceAtLeast(0)
        return value.take(keep) + marker
    }

    private fun sha256Local(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun installBlocking(): Map<String, Any?> {
        if (!abiSupported()) return finishError("unsupported_abi: ${selectedAbi()}")
        storagePreflightForInstall()?.let { return it }
        val missing = missingRuntimeFiles()
        if (missing.isNotEmpty()) return finishError("missing_runtime_files: ${missing.joinToString(",")}")
        runtimeDir.mkdirs()
        updateInstall("initializing", "Preparing ARCH Linux Runtime install", mapOf("selfTestAttempted" to false, "runtimeVersion" to ArchRuntimeManifest.runtimeVersion, "displayRuntimeVersion" to ArchRuntimeManifest.displayRuntimeVersion, "prootVersion" to ArchRuntimeManifest.prootVersion))
        cleanIncompleteInstall("installer_retry_start")
        val stagingDir = freshInstallingDir()
        if (!stagingDir.mkdirs()) throw IllegalStateException("staging_create_failed: ${stagingDir.absolutePath}")
        event("staging_created", mapOf("path" to stagingDir.absolutePath))
        updateInstall("extracting", "Extracting minimal Arch rootfs", mapOf("extractorName" to "RootfsBundleInstaller"))
        val extraction = RootfsBundleInstaller(activity.assets, stagingDir, cacheDir).install()
        updateInstall("extracting", "Rootfs bundle extracted", extraction.toInstallMetadata())
        if (!extraction.success) return finishError("rootfs_extract_failed: ${extraction.error ?: "unknown"}")
        initializeRootfs(stagingDir)
        val stagingValidation = validateRootfs(stagingDir)
        updateValidation("staging", stagingValidation)
        if (!stagingValidation.ready) return finishError("staging_rootfs_validation_failed: ${stagingValidation.summary}")
        replaceRootfsWith(stagingDir)?.let { return it }
        val finalValidation = validateRootfs(rootfsDir)
        updateValidation("final", finalValidation)
        if (!finalValidation.ready) return finishError("final_rootfs_validation_failed: ${finalValidation.summary}")
        writeRootfsReadyMetadata()
        return runSelfTestOnly()
    }

    private fun runSelfTestOnly(): Map<String, Any?> {
        val validation = validateRootfs(rootfsDir)
        if (!runtimeMetadataMatches(metadata()) || !validation.ready) return finishError("rootfs_not_ready_for_self_test: ${validation.summary}")
        writeRootfsReadyMetadata()
        updateInstall("testing", "Running Arch runtime smoke test", mapOf("selfTestAttempted" to true, "installerCurrentlyValidating" to "none", "selfTestStages" to JSONArray()))
        event("self_test_started")
        val selfTest = selfTest()
        updateInstall("testing", "Running Arch runtime smoke test", mapOf("selfTestAttempted" to true, "selfTestCommand" to selfTest.command, "selfTestStdout" to selfTest.stdout.take(400), "selfTestStderr" to selfTest.stderr.take(400), "selfTestExitCode" to selfTest.exitCode))
        event("self_test_result", mapOf("success" to selfTest.success, "exitCode" to selfTest.exitCode, "stdout" to selfTest.stdout.take(120), "stderr" to selfTest.stderr.take(120)))
        if (!selfTest.success || selfTest.stdout.trim().lines().firstOrNull() != "hello") return finishError(selfTest.stderr.ifBlank { "runtime_init_failed" })
        val metadata = metadata() ?: baseInstallJson("ready", "ARCH Linux Runtime is ready.")
        metadata
            .put("runtimeKind", ArchRuntimeManifest.runtimeKind)
            .put("ready", true)
            .put("installInProgress", false)
            .put("state", "ready")
            .put("message", "ARCH Linux Runtime is ready.")
            .put("runtimeVersion", ArchRuntimeManifest.runtimeVersion)
            .put("displayRuntimeVersion", ArchRuntimeManifest.displayRuntimeVersion)
            .put("prootVersion", ArchRuntimeManifest.prootVersion)
            .put("rootfsVersion", ArchRuntimeManifest.rootfs.version)
            .put("distro", ArchRuntimeManifest.rootfs.distro)
            .put("architecture", selectedAbi())
            .put("bundleFormatVersion", ArchRuntimeManifest.rootfsBundle.formatVersion)
            .put("bundleChecksum", ArchRuntimeManifest.rootfsBundle.sha256)
            .put("bundleCompressedSize", ArchRuntimeManifest.rootfsBundle.compressedSize)
            .put("manifestEntryCount", ArchRuntimeManifest.rootfsBundle.manifestEntryCount)
            .put("installedAt", System.currentTimeMillis())
            .put("selfTestAttempted", true)
            .put("selfTestStdout", selfTest.stdout.take(400))
            .put("selfTestStderr", selfTest.stderr.take(400))
            .put("selfTestExitCode", selfTest.exitCode)
            .put("selfTestCommand", selfTest.command)
        metadataFile.writeText(metadata.toString(2))
        event("metadata_ready_written")
        return status()
    }

    private fun execute(id: String, command: String, activeProject: BoundProject?, projects: List<BoundProject>, timeout: Long): Map<String, Any?> {
        storagePreflightForPackageCommand(command)?.let { return it }
        val commandSpec = runtimeCommand(command, activeProject, projects)
        val result = runProot(id, commandSpec.args, activeProject?.host ?: runtimeDir, timeout, safeArgv(commandSpec.args), id)
        last = result
        return result.toMap()
    }

    private fun minimalRuntimeCommand(command: String, shell: String = "/bin/sh", shellFlag: String = "-c"): List<String> = buildList {
        add(launcher.absolutePath)
        add("-r")
        add(rootfsDir.absolutePath)
        add("-0")
        add("--link2symlink")
        systemBinds().forEach { bind -> add("-b"); add(bind) }
        add("-w")
        add("/root")
        add(shell)
        add(shellFlag)
        add(command)
    }

    private fun runtimeCommand(command: String, activeProject: BoundProject?, availableProjects: List<BoundProject>): PRootCommand {
        val projects = (availableProjects + listOfNotNull(activeProject)).filter { it.host.exists() }.distinctBy { it.guestPath }
        ensureWorkspaceMountpoints(projects)
        val workdir = activeProject?.guestPath ?: "/root"
        val args = buildList {
            add(launcher.absolutePath)
            add("-r")
            add(rootfsDir.absolutePath)
            add("-0")
            add("--link2symlink")
            systemBinds().forEach { bind -> add("-b"); add(bind) }
            projects.forEach { project ->
                add("-b")
                add("${project.host.absolutePath}:${project.guestPath}")
            }
            add("-w")
            add(workdir)
            add("/bin/bash")
            add("-lc")
            add(wrapPackageCommand(command))
        }
        return PRootCommand(args, workdir)
    }

    private fun systemBinds(): List<String> = listOf("/dev", "/proc", "/sys", "/system", "/storage")
        .filter { File(it).exists() }
        .map { "$it:$it" }

    private fun parseProjects(raw: Any?): List<BoundProject> {
        val list = raw as? List<*> ?: return emptyList()
        return list.mapNotNull { parseProject(it as? Map<*, *>) }
    }

    private fun parseProject(raw: Map<*, *>?): BoundProject? {
        val folderPath = raw?.get("folderPath")?.toString()?.takeIf { it.isNotBlank() } ?: return null
        val mountName = raw["mountName"]?.toString()?.takeIf { it.isNotBlank() } ?: mountNameForPath(folderPath)
        return BoundProject(File(folderPath), safeMountName(mountName))
    }

    private fun mountNameForPath(path: String): String = safeMountName(File(path).name.ifBlank { "project" }.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-'))

    private fun safeMountName(name: String): String {
        val normalized = name.lowercase().replace(Regex("[^a-z0-9-]+"), "-").replace(Regex("-+"), "-").trim('-')
        return normalized.takeIf { it.isNotBlank() && it != "." && it != ".." } ?: "project"
    }

    private fun ensureWorkspaceMountpoints(projects: List<BoundProject>) {
        val workspace = File(rootfsDir, "workspace")
        workspace.mkdirs()
        try { Os.chmod(workspace.absolutePath, 0x1ed) } catch (_: Exception) { workspace.setReadable(true, false) }
        projects.forEach { project ->
            val mount = File(workspace, project.mountName)
            mount.mkdirs()
            try { Os.chmod(mount.absolutePath, 0x1ed) } catch (_: Exception) { mount.setReadable(true, false) }
        }
    }

    private fun selfTest(): LocalRunResult {
        val shEcho = runSelfTestStage("Test 1: sh echo", minimalRuntimeCommand("echo hello", "/bin/sh", "-c"), runtimeDir)
        if (!shEcho.success || shEcho.stdout.trim() != "hello") return shEcho
        val bashEcho = runSelfTestStage("Test 2: bash echo", minimalRuntimeCommand("echo hello", "/bin/bash", "-lc"), runtimeDir)
        if (!bashEcho.success || bashEcho.stdout.trim() != "hello") return bashEcho
        val uname = runSelfTestStage("Test 3: uname", minimalRuntimeCommand("uname -a", "/bin/sh", "-c"), runtimeDir)
        if (!uname.success) return uname
        val osRelease = runSelfTestStage("Test 4: os-release", minimalRuntimeCommand("cat /etc/os-release", "/bin/sh", "-c"), runtimeDir)
        if (!osRelease.success || !osRelease.stdout.contains("Arch")) return osRelease
        val pacman = runSelfTestStage("Test 5: pacman --version", minimalRuntimeCommand("pacman --version", "/bin/sh", "-c"), runtimeDir)
        if (!pacman.success) return pacman
        val dbVersion = runSelfTestStage("Test 6: pacman local db version", minimalRuntimeCommand("test \"\$(cat /var/lib/pacman/local/ALPM_DB_VERSION)\" = \"9\"", "/bin/sh", "-c"), runtimeDir)
        if (!dbVersion.success) return dbVersion
        val keyringDir = runSelfTestStage("Test 7: pacman keyring directory", minimalRuntimeCommand("test -d /etc/pacman.d/gnupg", "/bin/sh", "-c"), runtimeDir)
        if (!keyringDir.success) return keyringDir
        val projectA = File(runtimeDir, "selftest_project_a")
        val projectB = File(runtimeDir, "selftest_project_b")
        projectA.mkdirs()
        projectB.mkdirs()
        File(projectA, "a.txt").writeText("from a")
        File(projectB, "b.txt").writeText("from b")
        val workspaceTest = runSelfTestStage(
            "Test 8: workspace bind pwd",
            runtimeCommand("pwd && cat /workspace/project-b/b.txt && echo \"written from linux\" > linux-test.txt", BoundProject(projectA, "project-a"), listOf(BoundProject(projectA, "project-a"), BoundProject(projectB, "project-b"))).args,
            projectA,
        )
        if (!workspaceTest.success || workspaceTest.stdout.lines().firstOrNull()?.trim() != "/workspace/project-a") return workspaceTest
        val linuxWrite = File(projectA, "linux-test.txt")
        if (!linuxWrite.exists() || linuxWrite.readText().trim() != "written from linux") {
            return LocalRunResult(command = workspaceTest.command, stdout = workspaceTest.stdout, stderr = "workspace_write_coherence_failed", exitCode = -1, durationMs = workspaceTest.durationMs, errorCategory = "workspace_write_coherence_failed")
        }
        return shEcho
    }

    private fun runSelfTestStage(name: String, args: List<String>, directory: File, timeoutSeconds: Long = 20): LocalRunResult {
        val result = runProot(name.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-'), args, directory, timeoutSeconds, safeArgv(args))
        last = result
        recordSelfTestStage(name, result)
        return result
    }

    private fun recordSelfTestStage(name: String, result: LocalRunResult) {
        val current = metadata() ?: return
        val stages = current.optJSONArray("selfTestStages") ?: JSONArray()
        stages.put(JSONObject().put("name", name).put("argv", result.command).put("exit", result.exitCode).put("stdout", result.stdout.take(800)).put("stderr", result.stderr.take(800)).put("runtimeSignal", result.runtimeSignal ?: "none"))
        current.put("selfTestStages", stages)
        metadataFile.writeText(current.toString(2))
    }

    private fun runProot(id: String, args: List<String>, directory: File, timeout: Long, displayCommand: String, outputCommandId: String? = null): LocalRunResult {
        val started = System.currentTimeMillis()
        val builder = ProcessBuilder(args).directory(directory)
        configureProotEnvironment(builder)
        val process = try {
            builder.start()
        } catch (error: Exception) {
            return LocalRunResult(command = displayCommand, stderr = safe(error), exitCode = -1, durationMs = System.currentTimeMillis() - started, errorCategory = "process_start_failed")
        }
        active[id] = process
        val stdout = readAsync(process.inputStream) { text, snapshot, truncated, originalLength ->
            outputCommandId?.let { emitRuntimeOutput(it, "stdout", text, snapshot, truncated, originalLength) }
        }
        val stderr = readAsync(process.errorStream) { text, snapshot, truncated, originalLength ->
            outputCommandId?.let { emitRuntimeOutput(it, "stderr", text, snapshot, truncated, originalLength) }
        }
        val finished = process.waitFor(timeout, TimeUnit.SECONDS)
        if (!finished) process.destroyForcibly()
        val code = if (finished) process.exitValue() else -1
        active.remove(id)
        val wasCancelled = cancelled.remove(id)
        val signal = runtimeSignal(code)
        return LocalRunResult(command = displayCommand, stdout = stdout(), stderr = stderr(), exitCode = code, durationMs = System.currentTimeMillis() - started, timedOut = !finished && !wasCancelled, cancelled = wasCancelled, errorCategory = when { wasCancelled -> "cancelled"; code == 0 && finished -> null; !finished -> "command_timeout"; signal != null -> "runtime_signal"; else -> null }, runtimeSignal = if (wasCancelled) null else signal, guestExitCode = if (!wasCancelled && signal != null) code else null)
    }

    private fun emitRuntimeOutput(id: String, stream: String, text: String, snapshot: String, truncated: Boolean, originalLength: Long) {
        emitCommandOutput(
            mapOf(
                "id" to id,
                "stream" to stream,
                "text" to text,
                "${stream}Preview" to snapshot,
                "${stream}Truncated" to truncated,
                "${stream}OriginalLength" to originalLength,
            )
        )
    }

    private fun configureProotEnvironment(builder: ProcessBuilder) {
        val env = builder.environment()
        env.clear()
        env["PROOT_TMP_DIR"] = prepareProotTmpDir().absolutePath
        env["PROOT_LOADER"] = File(nativeDir, "libsyntac_proot_loader.so").absolutePath
    }

    private fun initializeRootfs(rootfs: File) {
        val tmp = prepareProotTmpDir()
        ensureRootfsCompatibilityLinks(rootfs)
        listOf("tmp", "var/tmp", "etc/pacman.d/gnupg", "var/cache/pacman/pkg", "var/lib/pacman/sync").forEach { path ->
            val dir = File(rootfs, path)
            dir.mkdirs()
            val mode = if (path == "etc/pacman.d/gnupg") 0x1c0 else 0x1ff
            try { Os.chmod(dir.absolutePath, mode) } catch (_: Exception) { dir.setWritable(true, false) }
        }
        File(rootfs, "workspace").mkdirs()
        updateInstall("initializing", "Initializing Arch runtime", mapOf("prootTmpDir" to tmp.absolutePath, "prootTmpExists" to tmp.exists(), "prootTmpWritable" to canWriteProbe(tmp)))
    }

    private fun ensureRootfsCompatibilityLinks(rootfs: File) {
        ensureRootfsSymlink(rootfs, "bin", "usr/bin")
        ensureRootfsSymlink(rootfs, "sbin", "usr/bin")
        ensureRootfsSymlink(rootfs, "lib", "usr/lib")
        ensureBinShellFallback(rootfs)
    }

    private fun ensureRootfsSymlink(rootfs: File, path: String, target: String) {
        val link = File(rootfs, path)
        val targetFile = File(rootfs, target)
        if (!targetFile.exists()) return
        if (isSymlink(link) && safeReadlink(link) == target) return
        if (existsNoFollow(link)) deletePath(link, "repair_rootfs_link_$path")
        try {
            Os.symlink(target, link.absolutePath)
        } catch (_: Exception) {
            if (!link.exists()) link.mkdirs()
        }
    }

    private fun ensureBinShellFallback(rootfs: File) {
        val bin = File(rootfs, "bin")
        if (isSymlink(bin)) return
        bin.mkdirs()
        listOf("sh", "bash").forEach { name ->
            val link = File(bin, name)
            if (existsNoFollow(link)) return@forEach
            try {
                Os.symlink("../usr/bin/$name", link.absolutePath)
            } catch (_: Exception) {
                val source = File(rootfs, "usr/bin/$name")
                if (source.isFile) source.copyTo(link, overwrite = true)
            }
        }
    }

    private fun finishError(message: String): Map<String, Any?> {
        event("install_error", mapOf("message" to message))
        updateInstall("error", message, mapOf("lastInstallException" to message, "installInProgress" to false, "installerCurrentlyValidating" to "none"))
        return status()
    }

    private fun writeRootfsReadyMetadata() {
        val current = metadata() ?: baseInstallJson("testing", "Running Arch runtime smoke test")
        current.put("runtimeKind", ArchRuntimeManifest.runtimeKind)
            .put("ready", false)
            .put("installInProgress", true)
            .put("rootfsReady", true)
            .put("state", "testing")
            .put("message", "Arch rootfs validated; running runtime smoke test.")
            .put("runtimeVersion", ArchRuntimeManifest.runtimeVersion)
            .put("prootVersion", ArchRuntimeManifest.prootVersion)
            .put("rootfsVersion", ArchRuntimeManifest.rootfs.version)
            .put("distro", ArchRuntimeManifest.rootfs.distro)
            .put("architecture", selectedAbi())
            .put("bundleFormatVersion", ArchRuntimeManifest.rootfsBundle.formatVersion)
            .put("bundleChecksum", ArchRuntimeManifest.rootfsBundle.sha256)
            .put("bundleCompressedSize", ArchRuntimeManifest.rootfsBundle.compressedSize)
            .put("manifestEntryCount", ArchRuntimeManifest.rootfsBundle.manifestEntryCount)
        metadataFile.writeText(current.toString(2))
    }

    private fun updateInstall(state: String, message: String, extra: Map<String, Any?> = emptyMap()) {
        runtimeDir.mkdirs()
        val current = metadata()?.takeIf { metadataBelongsToCurrentRuntime(it) } ?: baseInstallJson(state, message)
        current.put("runtimeKind", ArchRuntimeManifest.runtimeKind)
        current.put("ready", if (state == "ready") current.optBoolean("ready") else false)
        current.put("state", state)
        current.put("message", message)
        current.put("updatedAt", System.currentTimeMillis())
        extra.forEach { (key, value) -> current.put(key, value ?: JSONObject.NULL) }
        metadataFile.writeText(current.toString(2))
    }

    private fun baseInstallJson(state: String, message: String): JSONObject = JSONObject()
        .put("runtimeKind", ArchRuntimeManifest.runtimeKind)
        .put("ready", false)
        .put("installInProgress", installRunning)
        .put("state", state)
        .put("message", message)
        .put("selectedAbi", selectedAbi())
        .put("runtimeVersion", ArchRuntimeManifest.runtimeVersion)
        .put("prootVersion", ArchRuntimeManifest.prootVersion)
        .put("rootfsVersion", ArchRuntimeManifest.rootfs.version)
        .put("distro", ArchRuntimeManifest.rootfs.distro)
        .put("bundleFormatVersion", ArchRuntimeManifest.rootfsBundle.formatVersion)
        .put("bundleChecksumExpected", ArchRuntimeManifest.rootfsBundle.sha256)
        .put("prootTmpDir", tmpDir.absolutePath)
        .put("selfTestAttempted", false)
        .put("installerCurrentlyValidating", "none")
        .put("installTimeline", JSONArray())
        .put("cleanupEvents", JSONArray())

    private fun updateValidation(label: String, validation: RootfsValidation) {
        val prefix = if (label == "staging") "staging" else "final"
        updateInstall(metadata()?.optString("state", "initializing") ?: "initializing", metadata()?.optString("message", "Initializing Arch runtime") ?: "Initializing Arch runtime", mapOf("${prefix}RootfsDirectoryExists" to validation.rootfsDirectoryExists, "${prefix}BinValid" to validation.binValid, "${prefix}BinShValid" to validation.binShValid, "${prefix}BinBashValid" to validation.binBashValid, "${prefix}PacmanValid" to validation.pacmanValid, "${prefix}ToolsValid" to validation.requiredToolsValid, "${prefix}CaCertsValid" to validation.caCertsValid, "${prefix}PacmanDbVersionValid" to validation.pacmanDbVersionValid, "${prefix}PacmanKeyringDirectoryValid" to validation.pacmanKeyringDirectoryValid, "${prefix}OsReleaseValid" to validation.osReleaseValid, "${prefix}DynamicLinkerValid" to validation.dynamicLinkerValid, "${prefix}ValidationSummary" to validation.summary))
    }

    private fun recoverInterruptedInstall() {
        val current = metadata() ?: return
        if (current.optBoolean("installInProgress") && !installRunning) {
            cleanIncompleteInstall("interrupted_install_recovery")
            updateInstall("notInstalled", "Previous install was interrupted; stale staging cleanup attempted.", mapOf("installInProgress" to false))
        }
    }

    private fun cleanIncompleteInstall(reason: String) {
        stagingDirs().forEach { deletePath(it, reason) }
    }

    private fun freshInstallingDir(): File = File(runtimeDir, "arch.installing.${System.currentTimeMillis()}")

    private fun stagingDirs(): List<File> = runtimeDir.listFiles()
        ?.filter { it.name == installingDir.name || it.name.startsWith("${installingDir.name}.") }
        ?: emptyList()

    private fun replaceRootfsWith(stagingDir: File): Map<String, Any?>? {
        if (rootfsDir.exists()) {
            val oldRootfs = File(runtimeDir, "arch.replaced.${System.currentTimeMillis()}")
            if (rootfsDir.renameTo(oldRootfs)) {
                deletePath(oldRootfs, "delete_replaced_rootfs")
            } else if (!deletePath(rootfsDir, "replace_previous_rootfs")) {
                return finishError("replace_previous_rootfs_failed: ${rootfsDir.absolutePath}")
            }
        }
        if (!stagingDir.renameTo(rootfsDir)) return finishError("atomic_rename_failed: ${stagingDir.absolutePath}")
        return null
    }

    private fun deletePath(path: File, reason: String): Boolean {
        if (!existsNoFollow(path)) return true
        val deleted = if (isSymlink(path)) {
            path.delete()
        } else {
            makeDeletable(path)
            path.deleteRecursively()
        }
        addCleanupEvent(path.absolutePath, reason, deleted)
        return deleted
    }

    private fun makeDeletable(path: File) {
        if (!existsNoFollow(path) || isSymlink(path)) return
        if (path.isDirectory) {
            try { Os.chmod(path.absolutePath, 0x1ff) } catch (_: Exception) { path.setWritable(true, false) }
            path.listFiles()?.forEach { makeDeletable(it) }
        } else {
            try { Os.chmod(path.absolutePath, 0x180) } catch (_: Exception) { path.setWritable(true, true) }
        }
    }

    private fun prepareProotTmpDir(): File {
        val tmp = File(tmpDir, "proot")
        tmp.mkdirs()
        try { Os.chmod(tmp.absolutePath, 0x1c0) } catch (_: Exception) { tmp.setWritable(true, true) }
        return tmp
    }

    private fun canWriteProbe(dir: File): Boolean = try {
        dir.mkdirs()
        val probe = File(dir, ".probe-${System.nanoTime()}")
        probe.writeText("ok")
        probe.delete()
    } catch (_: Exception) {
        false
    }

    private fun storagePreflightForInstall(): Map<String, Any?>? {
        val required = ArchRuntimeManifest.rootfsBundle.installedSizeBytes +
            (ArchRuntimeManifest.rootfsBundle.compressedSize * 2L) +
            minFreeAfterInstallBytes
        val free = activity.filesDir.usableSpace
        if (free >= required) return null
        return finishError("low_storage: free=$free required=$required operation=install_rootfs")
    }

    private fun storagePreflightForPackageCommand(command: String): Map<String, Any?>? {
        if (!shouldManagePacmanCache(command)) return null
        val free = activity.filesDir.usableSpace
        if (free >= minFreeBeforePackageBytes) return null
        return runFailure("low_storage", "low_storage: free=$free required=$minFreeBeforePackageBytes operation=pacman")
    }

    private fun shouldManagePacmanCache(command: String): Boolean =
        Regex("""(^|[;&|()\s])(?:sudo\s+)?pacman\s+[^;&|]*-[A-Za-z]*S""").containsMatchIn(command)

    private fun wrapPackageCommand(command: String): String {
        if (!shouldManagePacmanCache(command)) return command
        return "{ if ! pacman-key --list-keys >/dev/null 2>&1; then pacman-key --init && pacman-key --populate archlinuxarm || exit \$?; fi; $command; status=\$?; if [ \$status -eq 0 ]; then rm -f /var/cache/pacman/pkg/*.pkg.tar.* /var/cache/pacman/pkg/*.sig; fi; exit \$status; }"
    }

    private fun packageCacheSize(): Long {
        val cache = File(rootfsDir, "var/cache/pacman/pkg")
        return cache.listFiles()?.filter { it.isFile }?.sumOf { it.length() } ?: 0L
    }

    private fun runtimeSizeEstimate(cacheSize: Long): Long =
        if (rootfsDir.exists()) ArchRuntimeManifest.rootfsBundle.installedSizeBytes + cacheSize + cacheDirSize() + tmpDirSize() else cacheDirSize() + tmpDirSize()

    private fun cacheDirSize(): Long = cacheDir.listFiles()?.filter { it.isFile }?.sumOf { it.length() } ?: 0L

    private fun tmpDirSize(): Long = tmpDir.listFiles()?.filter { it.isFile }?.sumOf { it.length() } ?: 0L

    private fun validateRootfs(rootfs: File): RootfsValidation {
        val bin = resolveRootfsPath(rootfs, "bin")
        val sh = resolveRootfsPath(rootfs, "bin/sh")
        val bash = resolveRootfsPath(rootfs, "bin/bash")
        val pacman = resolveRootfsPath(rootfs, "usr/bin/pacman")
        val osRelease = resolveRootfsPath(rootfs, "etc/os-release")
        val linker = resolveRootfsPath(rootfs, "usr/lib/ld-linux-aarch64.so.1")
        val caCerts = resolveRootfsPath(rootfs, "etc/ssl/certs/ca-certificates.crt")
        val dbVersion = resolveRootfsPath(rootfs, "var/lib/pacman/local/ALPM_DB_VERSION")
        val keyring = resolveRootfsPath(rootfs, "etc/pacman.d/gnupg")
        val tools = listOf("usr/bin/ls", "usr/bin/curl", "usr/bin/find", "usr/bin/grep", "usr/bin/sed", "usr/bin/awk", "usr/bin/tar", "usr/bin/gzip", "usr/bin/xz", "usr/bin/zstd").all { resolveRootfsPath(rootfs, it).valid }
        return RootfsValidation(rootfs.absolutePath, rootfs.exists(), bin.valid, File(rootfs, "usr").exists(), File(rootfs, "etc").exists(), sh.entryExists, sh.valid, bash.valid, pacman.valid, osRelease.valid, linker.valid, tools, caCerts.valid, dbVersion.valid, keyring.valid, sh.type, sh.linkTarget, sh.resolvedRootfsTarget)
    }

    private fun resolveRootfsPath(rootfs: File, relativePath: String): RootfsPathValidation {
        val pending = relativePath.split('/').filter { it.isNotBlank() && it != "." }.toMutableList()
        var current = normalizeAbsolute(rootfs)
        val seen = mutableSetOf<String>()
        for (index in 0 until 80) {
            if (!isWithinRoot(rootfs, current)) return RootfsPathValidation(false, false, "escaped", null, null, null)
            if (pending.isEmpty()) {
                val exists = existsNoFollow(current)
                if (!exists) return RootfsPathValidation(false, false, "missing", null, null, null)
                if (isSymlink(current)) {
                    if (!seen.add(current.absolutePath)) return RootfsPathValidation(true, false, "symlink-cycle", safeReadlink(current), null, null)
                    val target = normalizeRootfsPath(rootfs, safeReadlink(current).orEmpty(), current.parentFile ?: rootfs)
                    current = target
                    continue
                }
                return RootfsPathValidation(true, true, if (current.isDirectory) "directory" else "file", null, rootfsRelative(rootfs, current), current)
            }
            val next = normalizeRootfsPath(rootfs, pending.removeAt(0), current)
            if (!existsNoFollow(next)) return RootfsPathValidation(false, false, "missing", null, null, null)
            if (isSymlink(next)) {
                val linkTarget = safeReadlink(next)
                if (!seen.add(next.absolutePath)) return RootfsPathValidation(true, false, "symlink-cycle", linkTarget, null, null)
                current = normalizeRootfsPath(rootfs, linkTarget.orEmpty(), next.parentFile ?: rootfs)
            } else {
                current = next
            }
        }
        return RootfsPathValidation(false, false, "too-deep", null, null, null)
    }

    private fun normalizeRootfsPath(rootfs: File, path: String, parent: File): File {
        val raw = if (path.startsWith('/')) File(rootfs, path.trimStart('/')) else File(parent, path)
        return normalizeAbsolute(raw)
    }

    private fun rootfsRelative(rootfs: File, file: File): String = normalizeAbsolute(file).absolutePath.removePrefix(normalizeAbsolute(rootfs).absolutePath).trimStart('/').ifBlank { "." }

    private fun lightweightDetails(state: String, current: JSONObject?): String = listOf(
        "Runtime implementation: Open-source Termux PRoot",
        "State: $state",
        "Rootfs installed: ${rootfsDir.exists()}",
        "Install running: $installRunning",
        "Runtime version: ${ArchRuntimeManifest.displayRuntimeVersion}",
        "Rootfs version: ${ArchRuntimeManifest.rootfs.version}",
        "Bundle size: ${ArchRuntimeManifest.rootfsBundle.compressedSize}",
        "Expected installed size: ${ArchRuntimeManifest.rootfsBundle.installedSizeBytes}",
        "Free app storage: ${activity.filesDir.usableSpace}",
        "Last error: ${current?.optString("lastInstallException", "none") ?: "none"}",
    ).joinToString("\n")

    private fun diagnostics(installed: Boolean): String {
        val tmpOk = try { canWriteProbe(prepareProotTmpDir()) } catch (_: Exception) { false }
        val current = metadata()?.takeIf { metadataBelongsToCurrentRuntime(it) }
        val final = validateRootfs(rootfsDir)
        val rootfs = ArchRuntimeManifest.rootfs
        val lines = mutableListOf(
            "Runtime implementation: Open-source Termux PRoot",
            "PROOT",
            "Version: ${ArchRuntimeManifest.prootVersion}",
            "Source: ${ArchRuntimeManifest.sourceUrl}",
            "Commit: ${ArchRuntimeManifest.sourceCommit}",
            "License: ${ArchRuntimeManifest.licenseSummary}",
            "License URL: ${ArchRuntimeManifest.licenseUrl}",
            "Selected ABI: ${selectedAbi()}",
            "Required ABI: ${ArchRuntimeManifest.architecture}",
            "Android version: ${Build.VERSION.RELEASE}",
            "Android SDK: ${Build.VERSION.SDK_INT}",
            "Kernel: ${System.getProperty("os.version") ?: "unknown"}",
            "Native launcher path: ${launcher.absolutePath}",
            "Packaged components:",
            componentDiagnostics(),
            "",
            "ROOTFS",
            "ARCH Linux Runtime version: ${ArchRuntimeManifest.displayRuntimeVersion}",
            "Distro: ${rootfs.distro}",
            "Version: ${rootfs.version}",
            "Architecture: ${rootfs.architecture}",
            "Expected rootfs installed size: ${ArchRuntimeManifest.rootfsBundle.installedSizeBytes}",
            "Free app storage: ${activity.filesDir.usableSpace}",
            "Runtime directory size estimate: ${runtimeSizeEstimate(packageCacheSize())}",
            "Pacman cache size: ${packageCacheSize()}",
            "Source: ${ArchRuntimeManifest.rootfsSourceUrl}",
            "Source SHA256: ${ArchRuntimeManifest.rootfsSourceSha256}",
            "Bundle format version: ${ArchRuntimeManifest.rootfsBundle.formatVersion}",
            "Bundle compressed size: ${current?.optString("bundleCompressedSize", ArchRuntimeManifest.rootfsBundle.compressedSize.toString()) ?: ArchRuntimeManifest.rootfsBundle.compressedSize}",
            "Bundle checksum: ${current?.optString("bundleChecksum", "unknown") ?: "unknown"}",
            "Bundle checksum expected: ${ArchRuntimeManifest.rootfsBundle.sha256}",
            "Manifest entry count: ${current?.optString("manifestEntryCount", ArchRuntimeManifest.rootfsBundle.manifestEntryCount.toString()) ?: ArchRuntimeManifest.rootfsBundle.manifestEntryCount}",
            "Directories: ${current?.optString("bundleDirectories", "unknown") ?: "unknown"}",
            "Regular files: ${current?.optString("bundleRegularFiles", "unknown") ?: "unknown"}",
            "Symlinks: ${current?.optString("bundleSymlinks", "unknown") ?: "unknown"}",
            "Hard links: ${current?.optString("bundleHardLinks", "unknown") ?: "unknown"}",
            "Files materialized: ${current?.optString("filesMaterialized", "unknown") ?: "unknown"}",
            "Symlinks created: ${current?.optString("symlinksCreated", "unknown") ?: "unknown"}",
            "Install bytes: ${current?.optString("installBytesWritten", "unknown") ?: "unknown"}",
            "Install duration: ${current?.optString("installDurationMs", "unknown") ?: "unknown"} ms",
            "Bundle install success: ${current?.optString("bundleInstallSuccess", "false") ?: "false"}",
            "Bundle install error: ${current?.optString("bundleInstallError", "none") ?: "none"}",
            "Final path: ${rootfsDir.absolutePath}",
            "Final root exists: ${final.rootfsDirectoryExists}",
            "Final /bin valid: ${final.binValid}",
            "Final pacman DB version exists: ${final.pacmanDbVersionValid}",
            "Final pacman keyring directory exists: ${final.pacmanKeyringDirectoryValid}",
            "Final /bin/sh exists: ${final.binShValid}",
            "Final /bin/bash exists: ${final.binBashValid}",
            "Final pacman exists: ${final.pacmanValid}",
            "Final required tools exist: ${final.requiredToolsValid}",
            "Final CA certificates exist: ${final.caCertsValid}",
            "Final /etc/os-release exists: ${final.osReleaseValid}",
            "Final dynamic linker exists: ${final.dynamicLinkerValid}",
            "Final rootfs validation: ${if (final.ready) "pass" else "fail"}",
            "Detected OS: ${readOsRelease(rootfsDir)}",
            "Initialization: ${if (tmpOk) "pass" else "fail"}",
            "PROOT_TMP_DIR: ${tmpDir.absolutePath}",
            "PROOT_TMP_DIR writable: $tmpOk",
            "Rootfs installed: ${final.ready}",
            "Self-test attempted: ${current?.optString("selfTestAttempted", "false") ?: "false"}",
            "Self-test command: ${current?.optString("selfTestCommand", "unknown") ?: "unknown"}",
            "Self-test exit code: ${current?.optString("selfTestExitCode", "unknown") ?: "unknown"}",
            "Self-test stdout: ${current?.optString("selfTestStdout", "unknown") ?: "unknown"}",
            "Self-test stderr: ${current?.optString("selfTestStderr", "unknown") ?: "unknown"}",
            "SELF TEST STAGES",
            selfTestStageLines(current?.optJSONArray("selfTestStages")),
            "Last installation exception: ${current?.optString("lastInstallException", "none") ?: "none"}",
            "Cleanup events: ${jsonArrayLines(current?.optJSONArray("cleanupEvents"))}",
            "INSTALL TIMELINE",
            jsonArrayLines(current?.optJSONArray("installTimeline")),
            "",
            "EXECUTION",
            "Capability: ${capability(installed, final)}",
            "Project bind parent: /workspace",
            "Safe argv template: ${safeArgv(listOf(launcher.absolutePath, "-r", rootfsDir.absolutePath, "-0", "--link2symlink", "-b", "<project>:/workspace/<mount-name>", "-w", "/workspace/<mount-name>", "/bin/bash", "-lc", "<command>"))}",
            "Last command: ${last.command}",
            "Last exit code: ${last.exitCode}",
            "Last stdout preview: ${last.stdout.take(400)}",
            "Last stderr preview: ${last.stderr.take(400)}",
            "Last runtime error: ${last.errorCategory}",
        )
        return lines.joinToString("\n")
    }

    private fun capability(installed: Boolean, validation: RootfsValidation): String = when {
        missingRuntimeFiles().isNotEmpty() -> "PRootMissing"
        !validation.rootfsDirectoryExists -> "RootfsMissing"
        !validation.ready -> "RootfsCorrupt"
        installed -> "RuntimeReady"
        else -> "RootfsReady"
    }

    private fun componentDiagnostics(): String = ArchRuntimeManifest.prootFiles.joinToString("\n") { spec ->
        val file = File(nativeDir, spec.name)
        val actual = if (file.exists()) try { sha256Local(file) } catch (_: Exception) { "unreadable" } else "missing"
        "${spec.name}: found=${file.exists()} size=${file.length()} expectedSize=${spec.size} shaExpected=${spec.sha256} shaActual=$actual shaMatch=${actual == spec.sha256} mode=${fileMode(file)} machine=AArch64"
    }

    private fun event(name: String, extra: Map<String, Any?> = emptyMap()) {
        runtimeDir.mkdirs()
        val current = metadata()?.takeIf { metadataBelongsToCurrentRuntime(it) } ?: baseInstallJson("initializing", "Preparing ARCH Linux Runtime install")
        val timeline = current.optJSONArray("installTimeline") ?: JSONArray()
        val suffix = if (extra.isEmpty()) "" else " ${extra.entries.joinToString(" ") { "${it.key}=${it.value}" }}"
        timeline.put("${System.currentTimeMillis()} $name$suffix")
        current.put("installTimeline", timeline)
        metadataFile.writeText(current.toString(2))
    }

    private fun addCleanupEvent(path: String, reason: String, deleted: Boolean) {
        val current = metadata()?.takeIf { metadataBelongsToCurrentRuntime(it) } ?: baseInstallJson("initializing", "Preparing ARCH Linux Runtime install")
        val cleanup = current.optJSONArray("cleanupEvents") ?: JSONArray()
        cleanup.put("${System.currentTimeMillis()} Deleted: $path Reason: $reason Success: $deleted")
        current.put("cleanupEvents", cleanup)
        metadataFile.writeText(current.toString(2))
    }

    private fun missingRuntimeFiles(): List<String> = ArchRuntimeManifest.prootFiles.map { File(nativeDir, it.name) to it }.filter { (file, spec) -> !file.exists() || file.length() != spec.size }.map { it.second.name }
    private fun existsNoFollow(file: File): Boolean = try { Os.lstat(file.absolutePath); true } catch (_: Exception) { false }
    private fun isSymlink(file: File): Boolean = try { OsConstants.S_ISLNK(Os.lstat(file.absolutePath).st_mode) } catch (_: Exception) { false }
    private fun safeReadlink(file: File): String? = try { Os.readlink(file.absolutePath) } catch (_: Exception) { null }
    private fun fileMode(file: File): String = try { "0%o".format(Os.lstat(file.absolutePath).st_mode and 0x1ff) } catch (_: Exception) { "missing" }
    private fun jsonArrayLines(array: JSONArray?): String = if (array == null || array.length() == 0) "none" else (0 until array.length()).joinToString("\n") { array.optString(it) }

    private fun selfTestStageLines(array: JSONArray?): String {
        if (array == null || array.length() == 0) return "none"
        return (0 until array.length()).joinToString("\n") { index ->
            val item = array.optJSONObject(index)
            if (item == null) array.optString(index) else listOf(item.optString("name", "unknown"), "argv: ${item.optString("argv", "unknown")}", "exit: ${item.optString("exit", "unknown")}", "runtimeSignal: ${item.optString("runtimeSignal", "none")}", "stdout: ${item.optString("stdout", "")}", "stderr: ${item.optString("stderr", "")}").joinToString("\n")
        }
    }
    private fun metadataBelongsToCurrentRuntime(current: JSONObject): Boolean =
        current.optString("runtimeKind") == ArchRuntimeManifest.runtimeKind &&
            current.optString("runtimeVersion") == ArchRuntimeManifest.runtimeVersion &&
            current.optString("prootVersion") == ArchRuntimeManifest.prootVersion &&
            current.optString("rootfsVersion") == ArchRuntimeManifest.rootfs.version


    private fun runtimeMetadataMatches(current: JSONObject?): Boolean =
        current?.optString("runtimeKind") == ArchRuntimeManifest.runtimeKind &&
            current.optString("runtimeVersion") == ArchRuntimeManifest.runtimeVersion &&
            current.optString("prootVersion") == ArchRuntimeManifest.prootVersion &&
            current.optString("rootfsVersion") == ArchRuntimeManifest.rootfs.version &&
            current.optString("bundleChecksum") == ArchRuntimeManifest.rootfsBundle.sha256 &&
            current.optLong("bundleCompressedSize", -1) == ArchRuntimeManifest.rootfsBundle.compressedSize &&
            current.optInt("manifestEntryCount", -1) == ArchRuntimeManifest.rootfsBundle.manifestEntryCount

    private fun metadata(): JSONObject? = try { JSONObject(metadataFile.readText()) } catch (_: Exception) { null }
    private fun abiSupported(): Boolean = Build.SUPPORTED_ABIS.contains(ArchRuntimeManifest.architecture)
    private fun selectedAbi(): String = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
    private fun safe(error: Throwable): String = error.message ?: error.javaClass.simpleName
    private fun safeArgv(args: List<String>): String = args.mapIndexed { index, arg -> if (index > 0 && (args[index - 1] == "-c" || args[index - 1] == "-lc")) "<command>" else arg }.joinToString(" ")
    private fun runtimeSignal(code: Int): String? = when (code - 128) {
        6 -> "SIGABRT"
        7 -> "SIGBUS"
        8 -> "SIGFPE"
        9 -> "SIGKILL"
        11 -> "SIGSEGV"
        15 -> "SIGTERM"
        else -> if (code > 128) "SIG${code - 128}" else null
    }

    private fun readOsRelease(rootfs: File): String {
        val resolved = resolveRootfsPath(rootfs, "etc/os-release").resolvedFile ?: return "unknown"
        return try { resolved.readLines().firstOrNull { it.startsWith("PRETTY_NAME=") }?.substringAfter('=').orEmpty().trim('"').ifBlank { "unknown" } } catch (_: Exception) { "unknown" }
    }

    private fun normalizeAbsolute(file: File): File {
        val raw = file.absolutePath.replace('\\', '/')
        val prefix = if (raw.startsWith("/")) "/" else ""
        val parts = ArrayDeque<String>()
        raw.split('/').forEach { part ->
            when (part) {
                "", "." -> Unit
                ".." -> if (parts.isNotEmpty()) parts.removeLast()
                else -> parts.add(part)
            }
        }
        return File(prefix + parts.joinToString("/"))
    }

    private fun isWithinRoot(root: File, candidate: File): Boolean {
        val rootPath = normalizeAbsolute(root).absolutePath.trimEnd('/')
        val candidatePath = normalizeAbsolute(candidate).absolutePath.trimEnd('/')
        return candidatePath == rootPath || candidatePath.startsWith("$rootPath/")
    }

    private data class BoundProject(val host: File, val mountName: String) {
        val guestPath: String = "/workspace/$mountName"
    }

    private data class PRootCommand(val args: List<String>, val workdir: String)

    private data class RootfsPathValidation(
        val entryExists: Boolean,
        val valid: Boolean,
        val type: String,
        val linkTarget: String?,
        val resolvedRootfsTarget: String?,
        val resolvedFile: File?,
    )

    private data class RootfsValidation(
        val path: String,
        val rootfsDirectoryExists: Boolean,
        val binValid: Boolean,
        val usrExists: Boolean,
        val etcExists: Boolean,
        val binShExists: Boolean,
        val binShValid: Boolean,
        val binBashValid: Boolean,
        val pacmanValid: Boolean,
        val osReleaseValid: Boolean,
        val dynamicLinkerValid: Boolean,
        val requiredToolsValid: Boolean,
        val caCertsValid: Boolean,
        val pacmanDbVersionValid: Boolean,
        val pacmanKeyringDirectoryValid: Boolean,
        val binShType: String,
        val binShLinkTarget: String?,
        val binShResolvedRootfsTarget: String?,
    ) {
        val ready: Boolean = rootfsDirectoryExists && binValid && usrExists && etcExists && binShValid && binBashValid && pacmanValid && osReleaseValid && dynamicLinkerValid && requiredToolsValid && caCertsValid && pacmanDbVersionValid && pacmanKeyringDirectoryValid
        val summary: String = listOf("path=$path", "rootfs=$rootfsDirectoryExists", "bin=$binValid", "usr=$usrExists", "etc=$etcExists", "sh=$binShValid", "bash=$binBashValid", "pacman=$pacmanValid", "tools=$requiredToolsValid", "caCerts=$caCertsValid", "pacmanDb=$pacmanDbVersionValid", "pacmanKeyring=$pacmanKeyringDirectoryValid", "osRelease=$osReleaseValid", "linker=$dynamicLinkerValid").joinToString(", ")
    }
}
