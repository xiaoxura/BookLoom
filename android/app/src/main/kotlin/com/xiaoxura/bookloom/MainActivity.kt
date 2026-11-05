package com.xiaoxura.bookloom

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Collections
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val saveRequestCode = 0xB10
    private val shareRequestCode = 0xB11
    private var pendingSave: PendingSave? = null
    private var preparingShare = false
    private var pendingShareDirectory: File? = null
    private val activeShareDirectories = Collections.synchronizedSet(mutableSetOf<String>())

    // A receiving app may open the URI after the chooser closes. Keep copies for
    // seven days and reclaim only expired, inactive copies at a later startup.
    private val shareRetentionMillis = 7L * 24 * 60 * 60 * 1000

    private data class PendingSave(val source: File, val result: MethodChannel.Result)
    private class ShareCacheFull : IllegalStateException()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Thread { cleanExpiredShares() }.start()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookloom/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspectPermissions" -> {
                        try {
                            result.success(inspectPermissions())
                        } catch (error: Exception) {
                            result.error("inspection_failed", error.message ?: "Permission inspection failed", null)
                        }
                    }
                    "openSystemSettings" -> {
                        result.success(runCatching {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                            })
                            true
                        }.getOrDefault(false))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookloom/file_service")
            .setMethodCallHandler { call, result ->
                if (call.method != "savePreparedFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingSave != null) {
                    result.error("busy", "另一个保存对话框仍在打开。", null)
                    return@setMethodCallHandler
                }
                try {
                    val path = call.argument<String>("path") ?: throw IllegalArgumentException("path missing")
                    val name = call.argument<String>("fileName") ?: throw IllegalArgumentException("fileName missing")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val source = File(path).canonicalFile
                    val ownRoots = listOf(filesDir.canonicalFile, cacheDir.canonicalFile)
                    if (ownRoots.none { source.path.startsWith(it.path + File.separator) } || !source.isFile) {
                        throw IllegalArgumentException("prepared file is not in private app storage")
                    }

                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeType
                        putExtra(Intent.EXTRA_TITLE, name)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                    pendingSave = PendingSave(source, result)
                    startActivityForResult(intent, saveRequestCode)
                } catch (error: Exception) {
                    pendingSave = null
                    result.error("prepare_failed", error.message ?: "无法打开保存对话框。", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bookloom/sharing")
            .setMethodCallHandler { call, result ->
                if (call.method != "sharePreparedFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (preparingShare || pendingShareDirectory != null) {
                    result.error("busy", "另一个分享文件正在准备。", null)
                    return@setMethodCallHandler
                }
                preparingShare = true
                Thread {
                    var shareDirectory: File? = null
                    try {
                        val path = call.argument<String>("path")
                            ?: throw IllegalArgumentException("path missing")
                        val name = call.argument<String>("fileName")
                            ?: throw IllegalArgumentException("fileName missing")
                        val mimeType = call.argument<String>("mimeType")
                            ?: throw IllegalArgumentException("mimeType missing")
                        if (name.isBlank() || name != File(name).name ||
                            name.contains('\\') || name == "." || name == ".." ||
                            mimeType.isBlank() || mimeType.contains('\n') || mimeType.contains('\r')
                        ) {
                            throw IllegalArgumentException("invalid share metadata")
                        }
                        val source = File(path).canonicalFile
                        val exportRoot = File(cacheDir, "workbench").canonicalFile
                        val task = source.parentFile
                        if (exportRoot.parentFile != cacheDir.canonicalFile ||
                            !source.isFile || task == null || task.parentFile != exportRoot ||
                            !Regex("export-[A-Za-z0-9_-]+").matches(task.name) ||
                            !Regex("book\\.(epub|docx|html|txt|md)", RegexOption.IGNORE_CASE)
                                .matches(source.name)
                        ) {
                            throw IllegalArgumentException("not a completed private export")
                        }
                        val shareRoot = File(cacheDir, "bookloom-shares")
                        if (!shareRoot.exists() && !shareRoot.mkdirs()) {
                            throw IllegalStateException("cannot create share cache")
                        }
                        if (shareRoot.canonicalFile != File(cacheDir.canonicalFile, "bookloom-shares")) {
                            throw IllegalStateException("share cache path is not canonical")
                        }
                        cleanExpiredShares()
                        val retained = shareRoot.listFiles()?.filter { candidate ->
                            candidate.isDirectory &&
                                Regex("[0-9a-fA-F-]{36}").matches(candidate.name)
                        } ?: emptyList()
                        val retainedBytes = retained.sumOf { directory ->
                            directory.listFiles()?.sumOf { it.length() } ?: 0L
                        }
                        val maxCacheBytes = 512L * 1024 * 1024
                        if (retained.size >= 40 || source.length() > maxCacheBytes - retainedBytes) {
                            throw ShareCacheFull()
                        }
                        val readyDirectory = File(shareRoot, UUID.randomUUID().toString())
                        shareDirectory = readyDirectory
                        if (!readyDirectory.mkdir()) {
                            throw IllegalStateException("cannot create share directory")
                        }
                        val copy = File(readyDirectory, name)
                        FileInputStream(source).buffered().use { input ->
                            FileOutputStream(copy).buffered().use { output ->
                                input.copyTo(output, 64 * 1024)
                            }
                        }
                        runOnUiThread {
                            try {
                                activeShareDirectories.add(readyDirectory.path)
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.share-provider",
                                    copy,
                                )
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = mimeType
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    clipData = ClipData.newRawUri("", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                val chooser = Intent.createChooser(send, null).apply {
                                    clipData = ClipData.newRawUri("", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                pendingShareDirectory = readyDirectory
                                startActivityForResult(chooser, shareRequestCode)
                                // Android does not reliably report chooser cancellation or
                                // delivery. "opened" means only startActivity succeeded.
                                result.success("opened")
                            } catch (error: Exception) {
                                pendingShareDirectory = null
                                activeShareDirectories.remove(readyDirectory.path)
                                runCatching { readyDirectory.deleteRecursively() }
                                result.error("share_failed", error.message ?: "无法打开分享面板。", null)
                            } finally {
                                preparingShare = false
                            }
                        }
                    } catch (error: Exception) {
                        runCatching { shareDirectory?.deleteRecursively() }
                        runOnUiThread {
                            preparingShare = false
                            if (error is ShareCacheFull) {
                                result.error("cache_full", "分享暂存空间已满，请稍后重试。", null)
                            } else {
                                result.error("prepare_failed", error.message ?: "无法准备分享文件。", null)
                            }
                        }
                    }
                }.start()
            }
    }

    private fun inspectPermissions(): Map<String, Any> {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        }
        val requested = packageInfo.requestedPermissions ?: emptyArray()
        val flags = packageInfo.requestedPermissionsFlags
        if (requested.isNotEmpty() && (flags == null || flags.size != requested.size)) {
            throw IllegalStateException("Permission flags unavailable")
        }
        val broadStorage = setOf(
            "android.permission.READ_EXTERNAL_STORAGE",
            "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.MANAGE_EXTERNAL_STORAGE",
            "android.permission.READ_MEDIA_IMAGES",
            "android.permission.READ_MEDIA_VIDEO",
            "android.permission.READ_MEDIA_AUDIO",
        )
        val runtime = requested.mapIndexedNotNull { index, name ->
            val info = packageManager.getPermissionInfo(name, 0)
            if (info.protectionLevel and android.content.pm.PermissionInfo.PROTECTION_MASK_BASE !=
                android.content.pm.PermissionInfo.PROTECTION_DANGEROUS
            ) {
                null
            } else {
                val label = info.loadLabel(packageManager).toString().ifBlank { name }
                mapOf(
                    "name" to name,
                    "label" to label,
                    "granted" to (flags!![index] and PackageInfo.REQUESTED_PERMISSION_GRANTED != 0),
                )
            }
        }
        return mapOf(
            "runtimePermissions" to runtime,
            "declaresInternet" to requested.contains("android.permission.INTERNET"),
            "declaresBroadStorage" to requested.any { it in broadStorage },
        )
    }

    private fun cleanExpiredShares() {
        runCatching {
            val root = File(cacheDir, "bookloom-shares")
            if (!root.isDirectory || root.canonicalFile != File(cacheDir.canonicalFile, "bookloom-shares")) return
            val cutoff = System.currentTimeMillis() - shareRetentionMillis
            root.listFiles()?.forEach { entry ->
                if (entry.isDirectory && entry.lastModified() < cutoff &&
                    !activeShareDirectories.contains(entry.path) &&
                    Regex("[0-9a-fA-F-]{36}").matches(entry.name) &&
                    entry.canonicalFile.parentFile == root.canonicalFile
                ) {
                    entry.deleteRecursively()
                }
            }
        }
    }

    @Deprecated("Activity result bridge for ACTION_CREATE_DOCUMENT")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == shareRequestCode) {
            pendingShareDirectory?.let { activeShareDirectories.remove(it.path) }
            pendingShareDirectory = null
            return
        }
        if (requestCode != saveRequestCode) return
        val pending = pendingSave ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingSave = null
            pending.result.success(null)
            return
        }

        Thread {
            try {
                FileInputStream(pending.source).buffered().use { input ->
                    val output = contentResolver.openOutputStream(uri, "w")
                        ?: throw IllegalStateException("provider returned no output stream")
                    output.buffered().use { sink -> input.copyTo(sink, 64 * 1024) }
                }
                runOnUiThread {
                    pendingSave = null
                    pending.result.success(uri.toString())
                }
            } catch (error: Exception) {
                // CREATE_DOCUMENT creates a new document. Remove an incomplete one
                // when its provider allows deletion; never touch the source.
                try {
                    DocumentsContract.deleteDocument(contentResolver, uri)
                } catch (_: Exception) {
                    // Some providers do not support delete. Report the write failure.
                }
                runOnUiThread {
                    pendingSave = null
                    pending.result.error("write_failed", error.message ?: "无法写入所选位置。", null)
                }
            }
        }.start()
    }
}
