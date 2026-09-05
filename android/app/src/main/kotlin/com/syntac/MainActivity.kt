package com.syntac

import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.os.Environment

import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity : FlutterActivity() {
    private val channelName = "syntac/runtime"
    private var appForeground = false
    private lateinit var localRuntime: LocalRuntimeManager

    override fun onResume() {
        super.onResume()
        appForeground = true
    }

    override fun onStop() {
        appForeground = false
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        localRuntime = LocalRuntimeManager(this) { event ->
            runOnUiThread { channel.invokeMethod("commandOutput", event) }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "runtimeStatus" -> result.success(runtimeStatus())
                "runCommand" -> runCommand(call.arguments as? Map<*, *>, result)
                "cancelCommand" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("id")?.toString().orEmpty()
                    TermuxBridge.cancel(id)
                    result.success(null)
                }
                "localRuntimeStatus" -> result.success(localRuntime.status())
                "installLocalRuntime" -> localRuntime.install(result)
                "retryLocalRuntimeTest" -> localRuntime.retrySelfTest(result)
                "removeLocalRuntime" -> runLocalRuntimeRemove(result)
                "storageAccessStatus" -> result.success(storageAccessStatus())
                "openStorageSettings" -> {
                    openStorageSettings()
                    result.success(null)
                }
                "openUrl" -> {
                    val url = (call.arguments as? Map<*, *>)?.get("url")?.toString().orEmpty()
                    openExternalUrl(url)
                    result.success(null)
                }
                "runLocalCommand" -> localRuntime.runCommand(call.arguments as? Map<*, *>, result)
                "cancelLocalCommand" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("id")?.toString().orEmpty()
                    localRuntime.cancel(id)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }


    private fun runLocalRuntimeRemove(result: MethodChannel.Result) {
        Thread {
            val output = localRuntime.remove()
            runOnUiThread { result.success(output) }
        }.start()
    }

    private fun runtimeStatus(): Map<String, Any?> {
        val packageManager = packageManager
        val installed = try {
            packageManager.getPackageInfo("com.termux", 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
        if (!installed) {
            return mapOf(
                "state" to "unavailable",
                "message" to "Termux is not installed.",
                "details" to "Termux installed: no\nRUN_COMMAND available: no\n${storageAccessDetails()}\nApp foreground: ${if (appForeground) "yes" else "no"}\nLast Termux bridge result: ${TermuxBridge.lastBridgeResult}\nLast command launch state: ${TermuxBridge.lastLaunchState}\nLast runtime error category: ${TermuxBridge.lastRuntimeErrorCategory}\nInstall Termux from F-Droid or the official GitHub release."
            )
        }
        val runPermission = ContextCompat.checkSelfPermission(this, "com.termux.permission.RUN_COMMAND") == PackageManager.PERMISSION_GRANTED
        if (!runPermission) {
            return mapOf(
                "state" to "configurationRequired",
                "message" to "Grant Run commands in Termux environment permission to this app.",
                "details" to "Termux installed: yes\nRUN_COMMAND available: no\nallow-external-apps: unknown\n${storageAccessDetails()}\nApp foreground: ${if (appForeground) "yes" else "no"}\nLast Termux bridge result: ${TermuxBridge.lastBridgeResult}\nLast command launch state: ${TermuxBridge.lastLaunchState}\nLast runtime error category: ${TermuxBridge.lastRuntimeErrorCategory}\nAndroid Settings > Apps > Syntac > Permissions > Additional permissions."
            )
        }
        return mapOf(
            "state" to "ready",
            "message" to "Termux is installed and RUN_COMMAND permission is granted.",
            "details" to "Termux installed: yes\nRUN_COMMAND available: yes\nallow-external-apps: unknown\n${storageAccessDetails()}\nApp foreground: ${if (appForeground) "yes" else "no"}\nLast Termux bridge result: ${TermuxBridge.lastBridgeResult}\nLast command launch state: ${TermuxBridge.lastLaunchState}\nLast runtime error category: ${TermuxBridge.lastRuntimeErrorCategory}\nTermux must set allow-external-apps=true and have storage access for shared project paths."
        )
    }

    private fun storageAccessStatus(): Map<String, Any?> {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                ) == PackageManager.PERMISSION_GRANTED
        }
        return mapOf(
            "granted" to granted,
            "details" to storageAccessDetails()
        )
    }

    private fun openStorageSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                .setData(Uri.parse("package:$packageName"))
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    private fun openExternalUrl(url: String) {
        val uri = Uri.parse(url)
        if (uri.scheme != "https" && uri.scheme != "http") return
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
        } catch (ignored: Exception) {
        }
    }

    private fun storageAccessDetails(): String {
        val allFiles = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else false
        val legacyRead = ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        val legacyWrite = ContextCompat.checkSelfPermission(this, android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        return "All files access: ${if (allFiles) "yes" else "no"}\nLegacy external read: ${if (legacyRead) "yes" else "no"}\nLegacy external write: ${if (legacyWrite) "yes" else "no"}"
    }

    private fun runCommand(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val id = arguments?.get("id")?.toString().orEmpty()
        val command = arguments?.get("command")?.toString().orEmpty()
        val workingDirectory = arguments?.get("workingDirectory")?.toString().orEmpty()
        val timeoutSeconds = (arguments?.get("timeoutSeconds") as? Number)?.toLong() ?: 0L
        if (id.isBlank() || command.isBlank() || workingDirectory.isBlank()) {
            result.error("bad_args", "id, command, and workingDirectory are required", null)
            return
        }
        if (!appForeground) {
            TermuxBridge.register(id, result)
            TermuxBridge.markLaunch("blocked_background")
            TermuxBridge.fail(
                id,
                "Android blocked starting a Termux command while Syntac was in the background.",
                "TermuxBackgroundRestricted"
            )
            return
        }
        TermuxBridge.register(id, result)
        val callbackIntent = Intent(this, TermuxResultService::class.java).putExtra(TermuxResultService.extraCommandId, id)
        val pendingIntent = TermuxBridge.pendingIntent(this, id, callbackIntent)
        val bashPath = "/data/data/com.termux/files/usr/bin/bash"
        val commandPath = if (timeoutSeconds > 0) "/data/data/com.termux/files/usr/bin/timeout" else bashPath
        val commandArgs = if (timeoutSeconds > 0) arrayOf("${timeoutSeconds}s", bashPath, "-lc", command) else arrayOf("-lc", command)
        val intent = Intent()
            .setClassName("com.termux", "com.termux.app.RunCommandService")
            .setAction("com.termux.RUN_COMMAND")
            .putExtra("com.termux.RUN_COMMAND_PATH", commandPath)
            .putExtra("com.termux.RUN_COMMAND_ARGUMENTS", commandArgs)
            .putExtra("com.termux.RUN_COMMAND_WORKDIR", workingDirectory)
            .putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            .putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "Syntac")
            .putExtra("com.termux.RUN_COMMAND_COMMAND_DESCRIPTION", "Runs a project command requested by the active local coding-agent chat.")
            .putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pendingIntent)
        try {
            TermuxBridge.markLaunch("starting")
            startService(intent)
            TermuxBridge.markLaunch("started")
        } catch (error: Exception) {
            val message = error.message ?: error.javaClass.simpleName
            val backgroundRestricted = message.contains("background", ignoreCase = true) || error.javaClass.simpleName.contains("Background", ignoreCase = true)
            TermuxBridge.fail(
                id,
                if (backgroundRestricted) "Android blocked starting a Termux command while Syntac was in the background." else "Failed to start Termux command: $message",
                if (backgroundRestricted) "TermuxBackgroundRestricted" else "LaunchFailed"
            )
        }
    }

}
