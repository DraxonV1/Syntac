package com.syntac

import java.io.File
import java.security.MessageDigest

data class PRootRuntimeFile(
    val name: String,
    val sha256: String,
    val size: Long,
    val url: String,
)

data class RootfsArtifact(
    val distro: String,
    val version: String,
    val architecture: String,
    val fileName: String,
    val url: String,
    val sha256: String,
    val compressedSize: Long,
)

data class RootfsBundleArtifact(
    val runtimeVersion: String,
    val formatVersion: Int,
    val fileName: String,
    val assetPath: String,
    val sha256: String,
    val compressedSize: Long,
    val manifestEntryCount: Int,
    val installedSizeBytes: Long,
)

object ArchRuntimeManifest {
    const val runtimeKind = "termuxProotArch"
    const val runtimeVersion = "arch-linux-runtime-v1"
    const val displayRuntimeVersion = runtimeVersion
    const val prootVersion = "termux-proot-ab2e3464"
    const val architecture = "arm64-v8a"
    const val licenseSummary = "Open-source Termux PRoot; PRoot is GPLv2."
    const val licenseUrl = "https://github.com/termux/proot/blob/ab2e3464d04483b98a0614b470f3f8950d5a6468/COPYING"
    const val sourceUrl = "https://github.com/termux/proot"
    const val sourceCommit = "ab2e3464d04483b98a0614b470f3f8950d5a6468"
    const val rootfsSourceUrl = "https://github.com/termux/proot-distro/releases/download/v4.29.0/archlinux-aarch64-pd-v4.29.0.tar.xz"
    const val rootfsSourceSha256 = "08d74365213e647c558e561b0a2a7afb6fa3dfe345a1994c62ccac5af1a1cdc6"
    val prootFiles = listOf(
        PRootRuntimeFile(
            name = "libsyntac_proot.so",
            sha256 = "2d278e9a3f96ca275776909551c63eb878fb96a6d1b7a6b0c6f94e7f9a2e056a",
            size = 245816,
            url = "https://github.com/termux/proot/tree/ab2e3464d04483b98a0614b470f3f8950d5a6468",
        ),
        PRootRuntimeFile(
            name = "libsyntac_proot_loader.so",
            sha256 = "cf4f87772e1baf5950e35af9a729a1402898a81492e0aa011bcde3007455ddc8",
            size = 5464,
            url = "https://github.com/termux/proot/tree/ab2e3464d04483b98a0614b470f3f8950d5a6468",
        ),
    )

    val rootfs = RootfsArtifact(
        distro = "Arch Linux",
        version = "proot-distro-v4.29.0",
        architecture = "aarch64",
        fileName = "archlinux-aarch64-pd-v4.29.0.tar.xz",
        url = rootfsSourceUrl,
        sha256 = rootfsSourceSha256,
        compressedSize = 151744988,
    )

    val rootfsBundle = RootfsBundleArtifact(
        runtimeVersion = runtimeVersion,
        formatVersion = 2,
        fileName = "arch-linux-rootfs-v1.bundle",
        assetPath = "flutter_assets/assets/runtime/arch-linux-rootfs-v1.bundle",
        sha256 = "e9ba4ff277e432e503cec5e49c412502d398be125ee27bb441e0a2322f034d04",
        compressedSize = 126882630,
        manifestEntryCount = 30918,
        installedSizeBytes = 643931317,
    )
}

fun sha256(file: File): String {
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
