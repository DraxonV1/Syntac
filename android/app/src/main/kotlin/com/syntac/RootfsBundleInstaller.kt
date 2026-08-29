package com.syntac

import android.content.res.AssetManager
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.json.JSONArray
import org.json.JSONObject

class RootfsBundleInstaller(
    private val assets: AssetManager,
    private val destinationRoot: File,
    private val cacheDir: File,
) {
    fun install(): RootfsBundleInstallResult {
        val started = System.currentTimeMillis()
        val warnings = mutableListOf<String>()
        var bundleFile: File? = null
        var manifestEntryCount = 0
        var directories = 0
        var files = 0
        var symlinks = 0
        var hardLinks = 0
        var filesMaterialized = 0
        var symlinksCreated = 0
        var hardLinksCreated = 0
        var hardLinksCopied = 0
        var bytesWritten = 0L
        val fallbackDetails = mutableListOf<String>()

        try {
            cacheDir.mkdirs()
            bundleFile = copyBundleAssetToCache()
            val bundleSha = sha256Local(bundleFile)
            if (bundleSha != ArchRuntimeManifest.rootfsBundle.sha256) {
                throw IllegalStateException("bundle_checksum_mismatch: $bundleSha")
            }
            if (bundleFile.length() != ArchRuntimeManifest.rootfsBundle.compressedSize) {
                throw IllegalStateException("bundle_size_mismatch: ${bundleFile.length()}")
            }

            ZipFile(bundleFile).use { zip ->
                val manifestEntry = zip.getEntry("manifest.json") ?: throw IllegalStateException("bundle_manifest_missing")
                val manifest = JSONObject(zip.getInputStream(manifestEntry).bufferedReader().use { it.readText() })
                validateManifestHeader(manifest)
                val entries = parseEntries(manifest.getJSONArray("entries"))
                manifestEntryCount = entries.size
                val byPath = entries.associateBy { it.path }
                val seenPayload = mutableSetOf<String>()
                if (byPath.size != entries.size) throw IllegalStateException("duplicate_manifest_paths")

                directories = entries.count { it.type == EntryType.DIRECTORY }
                files = entries.count { it.type == EntryType.FILE }
                symlinks = entries.count { it.type == EntryType.SYMLINK }
                hardLinks = entries.count { it.type == EntryType.HARDLINK }

                val payload = manifest.getJSONObject("payload")
                val payloadName = payload.getString("name")
                val payloadSize = payload.getLong("size")
                val payloadSha = payload.getString("sha256")
                val payloadFile = copyPayloadToCache(zip, payloadName, payloadSize, payloadSha)
                val finalDirectoryModes = mutableListOf<Pair<File, Int>>()
                try {
                    TarArchiveInputStream(XZCompressorInputStream(FileInputStream(payloadFile))).use { tar ->
                        while (true) {
                            val tarEntry = tar.nextTarEntry ?: break
                            val path = safePayloadPath(tarEntry.name)
                            if (!seenPayload.add(path)) throw IllegalStateException("duplicate_payload_path: $path")
                            val entry = byPath[path] ?: throw IllegalStateException("payload_entry_not_in_manifest: $path")
                            when (entry.type) {
                                EntryType.DIRECTORY -> {
                                    val directory = destination(entry.path)
                                    ensureDirectoryWritable(directory)
                                    finalDirectoryModes.add(directory to entry.mode)
                                }
                                EntryType.FILE -> {
                                    val file = destination(entry.path)
                                    ensureParentDirectory(file)
                                    replaceExisting(file)
                                    val written = writeFile(tar, file, entry)
                                    restoreMode(file, entry.mode)
                                    filesMaterialized++
                                    bytesWritten += written
                                }
                                EntryType.SYMLINK -> {
                                    val target = entry.target ?: throw IllegalStateException("symlink_target_missing: ${entry.path}")
                                    val link = destination(entry.path)
                                    ensureParentDirectory(link)
                                    replaceExisting(link)
                                    Os.symlink(target, link.absolutePath)
                                    symlinksCreated++
                                }
                                EntryType.HARDLINK -> {
                                    val targetPath = resolveHardLinkTarget(entry, byPath)
                                    val target = destination(targetPath)
                                    if (!target.exists() && !isSymlink(target)) throw IllegalStateException("hard_link_target_missing: ${entry.path} -> ${entry.target}")
                                    val link = destination(entry.path)
                                    ensureParentDirectory(link)
                                    replaceExisting(link)
                                    try {
                                        Os.link(target.absolutePath, link.absolutePath)
                                        restoreMode(link, entry.mode)
                                        hardLinksCreated++
                                    } catch (error: Exception) {
                                        val copied = copyHardLinkFallback(target, link, entry.mode)
                                        bytesWritten += copied
                                        hardLinksCopied++
                                        val detail = "${entry.path} -> ${entry.target}: ${error.message ?: error.javaClass.simpleName}"
                                        fallbackDetails.add(detail)
                                        warnings.add("hard_link_copy_fallback: $detail")
                                    }
                                }
                            }
                        }
                        val missingPayload = byPath.keys - seenPayload
                        if (missingPayload.isNotEmpty()) {
                            throw IllegalStateException("manifest_entry_not_in_payload: ${missingPayload.sorted().take(5).joinToString(",")}")
                        }
                    }
                    finalDirectoryModes.sortedByDescending { it.first.absolutePath.length }.forEach { (directory, mode) ->
                        restoreMode(directory, mode)
                    }
                } finally {
                    payloadFile.delete()
                }
            }

            return RootfsBundleInstallResult(
                success = true,
                bundleAssetFound = true,
                bundleCompressedSize = bundleFile.length(),
                bundleChecksum = ArchRuntimeManifest.rootfsBundle.sha256,
                manifestEntryCount = manifestEntryCount,
                directories = directories,
                regularFiles = files,
                symlinks = symlinks,
                hardLinks = hardLinks,
                filesMaterialized = filesMaterialized,
                symlinksCreated = symlinksCreated,
                hardLinksCreated = hardLinksCreated,
                hardLinksCopied = hardLinksCopied,
                bytesWritten = bytesWritten,
                durationMs = System.currentTimeMillis() - started,
                warnings = warnings,
                error = null,
                hardLinkFallbackDetails = fallbackDetails,
            )
        } catch (error: Exception) {
            return RootfsBundleInstallResult(
                success = false,
                bundleAssetFound = bundleFile?.exists() == true,
                bundleCompressedSize = bundleFile?.length() ?: 0L,
                bundleChecksum = if (bundleFile?.exists() == true) try { sha256Local(bundleFile) } catch (_: Exception) { "unreadable" } else "missing",
                manifestEntryCount = manifestEntryCount,
                directories = directories,
                regularFiles = files,
                symlinks = symlinks,
                hardLinks = hardLinks,
                filesMaterialized = filesMaterialized,
                symlinksCreated = symlinksCreated,
                hardLinksCreated = hardLinksCreated,
                hardLinksCopied = hardLinksCopied,
                bytesWritten = bytesWritten,
                durationMs = System.currentTimeMillis() - started,
                warnings = warnings,
                error = error.message ?: error.javaClass.simpleName,
                hardLinkFallbackDetails = fallbackDetails,
            )
        }
    }

    private fun copyBundleAssetToCache(): File {
        val target = File(cacheDir, ArchRuntimeManifest.rootfsBundle.fileName)
        val partial = File(cacheDir, "${target.name}.part")
        partial.delete()
        assets.open(ArchRuntimeManifest.rootfsBundle.assetPath).use { input ->
            FileOutputStream(partial).use { output -> copy(input, output) }
        }
        if (!partial.renameTo(target)) throw IllegalStateException("bundle_cache_finalize_failed")
        return target
    }

    private fun copyPayloadToCache(zip: ZipFile, name: String, expectedSize: Long, expectedSha: String): File {
        val entry = zip.getEntry(name) ?: throw IllegalStateException("bundle_payload_missing: $name")
        val target = File(cacheDir, name)
        val partial = File(cacheDir, "$name.part")
        partial.delete()
        val digest = MessageDigest.getInstance("SHA-256")
        var copied = 0L
        zip.getInputStream(entry).use { input ->
            FileOutputStream(partial).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    digest.update(buffer, 0, read)
                    copied += read.toLong()
                }
            }
        }
        val actualSha = digest.digest().joinToString("") { "%02x".format(it) }
        if (copied != expectedSize) throw IllegalStateException("payload_size_mismatch: $copied")
        if (actualSha != expectedSha) throw IllegalStateException("payload_checksum_mismatch: $actualSha")
        if (!partial.renameTo(target)) throw IllegalStateException("payload_cache_finalize_failed")
        return target
    }

    private fun validateManifestHeader(manifest: JSONObject) {
        if (manifest.optInt("version") != ArchRuntimeManifest.rootfsBundle.formatVersion) throw IllegalStateException("bundle_format_mismatch")
        if (manifest.optString("runtimeVersion") != ArchRuntimeManifest.rootfsBundle.runtimeVersion) throw IllegalStateException("runtime_version_mismatch")
        if (manifest.optString("distro") != "archlinux") throw IllegalStateException("bundle_distro_mismatch")
        if (manifest.optString("distroVersion") != ArchRuntimeManifest.rootfs.version) throw IllegalStateException("bundle_distro_version_mismatch")
        if (manifest.optString("architecture") != ArchRuntimeManifest.rootfs.architecture) throw IllegalStateException("bundle_architecture_mismatch")
        if (manifest.optString("prootVersion") != ArchRuntimeManifest.prootVersion) throw IllegalStateException("bundle_proot_mismatch")
    }

    private fun parseEntries(array: JSONArray): List<BundleEntry> {
        val entries = mutableListOf<BundleEntry>()
        val seen = mutableSetOf<String>()
        for (index in 0 until array.length()) {
            val item = array.getJSONObject(index)
            val path = safeManifestPath(item.getString("path"))
            if (!seen.add(path)) throw IllegalStateException("duplicate_manifest_path: $path")
            val type = EntryType.fromManifest(item.getString("type"))
            entries.add(
                BundleEntry(
                    path = path,
                    type = type,
                    mode = item.optString("mode", "0000").toInt(8) and 0x1ff,
                    target = item.optString("target").takeIf { it.isNotBlank() },
                    sha256 = item.optString("sha256").takeIf { it.isNotBlank() },
                    size = item.optLong("size", 0L),
                ),
            )
        }
        return entries
    }

    private fun writeFile(input: InputStream, file: File, entry: BundleEntry): Long {
        val digest = MessageDigest.getInstance("SHA-256")
        var written = 0L
        FileOutputStream(file).use { output ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (written < entry.size) {
                val read = input.read(buffer, 0, minOf(buffer.size.toLong(), entry.size - written).toInt())
                if (read < 0) break
                output.write(buffer, 0, read)
                digest.update(buffer, 0, read)
                written += read.toLong()
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (written != entry.size) throw IllegalStateException("file_size_mismatch: ${entry.path}")
        if (actual != entry.sha256) throw IllegalStateException("file_checksum_mismatch: ${entry.path}")
        return written
    }

    private fun resolveHardLinkTarget(entry: BundleEntry, byPath: Map<String, BundleEntry>): String {
        var current = safeManifestPath(entry.target ?: throw IllegalStateException("hard_link_target_missing: ${entry.path}"))
        val seen = mutableSetOf<String>()
        while (true) {
            if (!seen.add(current)) throw IllegalStateException("hard_link_cycle: ${entry.path}")
            val target = byPath[current] ?: throw IllegalStateException("hard_link_target_missing: ${entry.path} -> $current")
            if (target.type != EntryType.HARDLINK) return current
            current = safeManifestPath(target.target ?: throw IllegalStateException("hard_link_target_missing: ${target.path}"))
        }
    }

    private fun destination(path: String): File {
        val file = normalizeAbsolute(File(destinationRoot, safeManifestPath(path)))
        if (!isWithinRoot(file)) throw IllegalStateException("path_escaped_root: $path")
        return file
    }

    private fun ensureParentDirectory(file: File) {
        ensureDirectoryWritable(file.parentFile ?: throw IllegalStateException("parent_missing: ${file.absolutePath}"))
    }

    private fun ensureDirectoryWritable(directory: File) {
        ensureNoSymlinkAncestor(directory)
        if (isSymlink(directory)) throw IllegalStateException("symlink_parent_escape_risk: ${directory.absolutePath}")
        if (directory.exists() && !directory.isDirectory) throw IllegalStateException("parent_not_directory: ${directory.absolutePath}")
        if (!directory.exists() && !directory.mkdirs()) throw IllegalStateException("directory_create_failed: ${directory.absolutePath}")
        try {
            Os.chmod(directory.absolutePath, 0x1c0)
        } catch (_: Exception) {
            directory.setReadable(true, false)
            directory.setWritable(true, true)
            directory.setExecutable(true, true)
        }
    }

    private fun safeManifestPath(raw: String): String {
        if (raw.isBlank() || raw.startsWith("/")) throw IllegalStateException("unsafe_manifest_path: $raw")
        val parts = ArrayDeque<String>()
        raw.replace('\\', '/').split('/').forEach { part ->
            when (part) {
                "", "." -> Unit
                ".." -> throw IllegalStateException("unsafe_manifest_path: $raw")
                else -> parts.add(part)
            }
        }
        return parts.joinToString("/").ifBlank { throw IllegalStateException("unsafe_manifest_path: $raw") }
    }

    private fun safePayloadPath(raw: String): String {
        val path = safeManifestPath(raw)
        if (path == SOURCE_PREFIX || path.startsWith("$SOURCE_PREFIX/")) throw IllegalStateException("payload_prefix_not_stripped: $raw")
        return path
    }

    private fun ensureNoSymlinkAncestor(directory: File) {
        val root = normalizeAbsolute(destinationRoot).absolutePath.trimEnd('/')
        val target = normalizeAbsolute(directory).absolutePath.trimEnd('/')
        if (target != root && !target.startsWith("$root/")) throw IllegalStateException("path_escaped_root: ${directory.absolutePath}")
        val relative = target.removePrefix(root).trimStart('/')
        if (relative.isBlank()) return
        var current = normalizeAbsolute(destinationRoot)
        relative.split('/').filter { it.isNotBlank() }.forEach { part ->
            current = File(current, part)
            if (isSymlink(current)) throw IllegalStateException("symlink_parent_escape_risk: ${current.absolutePath}")
        }
    }

    private fun copyHardLinkFallback(target: File, link: File, mode: Int): Long {
        if (isSymlink(target)) {
            Os.symlink(Os.readlink(target.absolutePath), link.absolutePath)
            return 0L
        }
        var copied = 0L
        FileInputStream(target).use { input ->
            FileOutputStream(link).use { output -> copied = copy(input, output) }
        }
        restoreMode(link, mode)
        return copied
    }

    private fun copy(input: InputStream, output: FileOutputStream): Long {
        var copied = 0L
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            output.write(buffer, 0, read)
            copied += read.toLong()
        }
        return copied
    }

    private fun replaceExisting(file: File) {
        if (!file.exists() && !isSymlink(file)) return
        if (file.isDirectory && !isSymlink(file)) {
            if (!file.deleteRecursively()) throw IllegalStateException("replace_directory_failed: ${file.absolutePath}")
        } else if (!file.delete()) {
            throw IllegalStateException("replace_file_failed: ${file.absolutePath}")
        }
    }

    private fun restoreMode(file: File, mode: Int) {
        if (mode == 0 || isSymlink(file)) return
        try {
            Os.chmod(file.absolutePath, mode)
        } catch (_: Exception) {
            file.setReadable(mode and 0x124 != 0, false)
            file.setWritable(mode and 0x92 != 0, false)
            file.setExecutable(mode and 0x49 != 0, false)
        }
    }

    private fun isSymlink(file: File): Boolean = try {
        OsConstants.S_ISLNK(Os.lstat(file.absolutePath).st_mode)
    } catch (_: Exception) {
        false
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

    private fun isWithinRoot(candidate: File): Boolean {
        val rootPath = normalizeAbsolute(destinationRoot).absolutePath.trimEnd('/')
        val candidatePath = normalizeAbsolute(candidate).absolutePath.trimEnd('/')
        return candidatePath == rootPath || candidatePath.startsWith("$rootPath/")
    }

    private companion object {
        const val SOURCE_PREFIX = "archlinux-aarch64"
    }

    private enum class EntryType {
        DIRECTORY,
        FILE,
        SYMLINK,
        HARDLINK;

        companion object {
            fun fromManifest(type: String): EntryType = when (type) {
                "directory" -> DIRECTORY
                "file" -> FILE
                "symlink" -> SYMLINK
                "hardlink" -> HARDLINK
                else -> throw IllegalStateException("invalid_entry_type: $type")
            }
        }
    }

    private data class BundleEntry(
        val path: String,
        val type: EntryType,
        val mode: Int,
        val target: String?,
        val sha256: String?,
        val size: Long,
    )
}

data class RootfsBundleInstallResult(
    val success: Boolean,
    val bundleAssetFound: Boolean,
    val bundleCompressedSize: Long,
    val bundleChecksum: String,
    val manifestEntryCount: Int,
    val directories: Int,
    val regularFiles: Int,
    val symlinks: Int,
    val hardLinks: Int,
    val filesMaterialized: Int,
    val symlinksCreated: Int,
    val hardLinksCreated: Int,
    val hardLinksCopied: Int,
    val bytesWritten: Long,
    val durationMs: Long,
    val warnings: List<String>,
    val error: String?,
    val hardLinkFallbackDetails: List<String>,
) {
    fun toInstallMetadata(): Map<String, Any?> = mapOf(
        "bundleAssetFound" to bundleAssetFound,
        "bundleFormatVersion" to ArchRuntimeManifest.rootfsBundle.formatVersion,
        "bundleCompressedSize" to bundleCompressedSize,
        "bundleChecksum" to bundleChecksum,
        "bundleChecksumExpected" to ArchRuntimeManifest.rootfsBundle.sha256,
        "bundleChecksumMatch" to (bundleChecksum == ArchRuntimeManifest.rootfsBundle.sha256),
        "manifestEntryCount" to manifestEntryCount,
        "bundleDirectories" to directories,
        "bundleRegularFiles" to regularFiles,
        "bundleSymlinks" to symlinks,
        "bundleHardLinks" to hardLinks,
        "filesMaterialized" to filesMaterialized,
        "symlinksCreated" to symlinksCreated,
        "hardLinksCreated" to hardLinksCreated,
        "hardLinksCopied" to hardLinksCopied,
        "installBytesWritten" to bytesWritten,
        "installDurationMs" to durationMs,
        "bundleInstallSuccess" to success,
        "bundleInstallWarnings" to warnings.joinToString("\n").ifBlank { "none" },
        "bundleInstallError" to (error ?: "none"),
        "hardLinkFallbackDetails" to hardLinkFallbackDetails.joinToString("\n").ifBlank { "none" },
    )
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

