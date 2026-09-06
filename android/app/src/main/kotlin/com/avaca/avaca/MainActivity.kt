package com.avaca.avaca

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import com.github.dart_lang.jni.JniPlugin
import com.github.dart_lang.jni_flutter.JniFlutterPlugin
import com.mr.flutter.plugin.filepicker.FilePickerPlugin
import com.tekartik.sqflite.SqflitePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val updateChannelName = "com.avaca.avaca/software_update"
    private val libraryStorageChannelName = "com.avaca.avaca/library_storage"
    private val mediaReadPermissionRequestCode = 4201
    private val libraryTreeRequestCode = 4202
    private var pendingMediaReadPermissionResult: MethodChannel.Result? = null
    private var pendingLibraryTreeResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugins = flutterEngine.plugins

        if (!plugins.has(JniPlugin::class.java)) {
            plugins.add(JniPlugin())
        }
        if (!plugins.has(JniFlutterPlugin::class.java)) {
            plugins.add(JniFlutterPlugin())
        }
        if (!plugins.has(SharedPreferencesPlugin::class.java)) {
            plugins.add(SharedPreferencesPlugin())
        }
        if (!plugins.has(SqflitePlugin::class.java)) {
            plugins.add(SqflitePlugin())
        }
        if (!plugins.has(FilePickerPlugin::class.java)) {
            plugins.add(FilePickerPlugin())
        }
        if (!plugins.has(FlutterAndroidLifecyclePlugin::class.java)) {
            plugins.add(FlutterAndroidLifecyclePlugin())
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )

                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "installApk" -> {
                        val apkPath = call.argument<String>("path")
                        if (apkPath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is missing.", null)
                            return@setMethodCallHandler
                        }
                        val apk = File(apkPath)
                        if (!apk.isFile) {
                            result.error("MISSING_APK", "APK file does not exist.", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apk
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, libraryStorageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickLibraryTree" -> pickLibraryTree(result)
                    "listLibraryDocuments" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri.isNullOrBlank()) {
                            result.error("INVALID_URI", "Library tree URI is missing.", null)
                            return@setMethodCallHandler
                        }
                        runLibraryStorageOperation(result) {
                            listLibraryDocuments(treeUri)
                        }
                    }
                    "statLibraryDocument" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val documentUri = call.argument<String>("documentUri")
                        if (treeUri.isNullOrBlank() || documentUri.isNullOrBlank()) {
                            result.error("INVALID_URI", "Library document URI is missing.", null)
                            return@setMethodCallHandler
                        }
                        runLibraryStorageOperation(result) {
                            statLibraryDocument(treeUri, documentUri)
                        }
                    }
                    "copyLibraryDocumentToPath" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val documentUri = call.argument<String>("documentUri")
                        val destinationPath = call.argument<String>("destinationPath")
                        if (treeUri.isNullOrBlank() ||
                            documentUri.isNullOrBlank() ||
                            destinationPath.isNullOrBlank()
                        ) {
                            result.error("INVALID_ARGUMENT", "Library copy arguments are missing.", null)
                            return@setMethodCallHandler
                        }
                        runLibraryStorageOperation(result) {
                            copyLibraryDocumentToPath(treeUri, documentUri, destinationPath)
                        }
                    }
                    "deleteLibraryDocument" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val documentUri = call.argument<String>("documentUri")
                        if (treeUri.isNullOrBlank() || documentUri.isNullOrBlank()) {
                            result.error("INVALID_URI", "Library document URI is missing.", null)
                            return@setMethodCallHandler
                        }
                        runLibraryStorageOperation(result) {
                            deleteLibraryDocument(treeUri, documentUri)
                        }
                    }
                    "requestMediaReadAccess" -> requestMediaReadAccess(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickLibraryTree(result: MethodChannel.Result) {
        if (pendingLibraryTreeResult != null) {
            result.error(
                "PICKER_IN_PROGRESS",
                "A library folder request is already in progress.",
                null,
            )
            return
        }
        pendingLibraryTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, libraryTreeRequestCode)
        } catch (error: Exception) {
            pendingLibraryTreeResult = null
            result.error("PICKER_UNAVAILABLE", "Unable to open the Android folder picker.", null)
        }
    }

    private fun runLibraryStorageOperation(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        try {
            result.success(operation())
        } catch (error: SecurityException) {
            Log.e("AvacaLibraryStorage", "Android folder permission is unavailable", error)
            result.error("PERMISSION_DENIED", "Android folder permission is unavailable.", null)
        } catch (error: FileNotFoundException) {
            Log.e("AvacaLibraryStorage", "Android source document is unavailable", error)
            result.error("DOCUMENT_NOT_FOUND", "Android source document is unavailable.", null)
        } catch (error: Exception) {
            Log.e("AvacaLibraryStorage", "Android source operation failed", error)
            result.error("STORAGE_OPERATION_FAILED", "Android source operation failed.", null)
        }
    }

    private fun ensureTreePermission(treeUri: Uri, requireWrite: Boolean = false) {
        val permissions = contentResolver.persistedUriPermissions
        val permission = permissions.firstOrNull { it.uri == treeUri }
        if (permission == null ||
            !permission.isReadPermission ||
            (requireWrite && !permission.isWritePermission)
        ) {
            throw SecurityException("persisted Android folder permission is missing")
        }
    }

    private fun pickLibraryTreeDisplayName(uri: Uri): String {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            uri,
            DocumentsContract.getTreeDocumentId(uri),
        )
        contentResolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                )
                if (index >= 0 && !cursor.isNull(index)) {
                    val name = cursor.getString(index).trim()
                    if (name.isNotEmpty()) return name
                }
            }
        }
        return "Android folder"
    }

    private fun listLibraryDocuments(treeUriString: String): List<Map<String, Any?>> {
        val treeUri = Uri.parse(treeUriString)
        ensureTreePermission(treeUri)
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val result = mutableListOf<Map<String, Any?>>()
        collectLibraryDocuments(
            treeUri = treeUri,
            documentId = rootDocumentId,
            relativeParent = "",
            result = result,
            visited = mutableSetOf(),
        )
        return result.sortedBy { it["relativePath"]?.toString()?.lowercase() ?: "" }
    }

    private fun collectLibraryDocuments(
        treeUri: Uri,
        documentId: String,
        relativeParent: String,
        result: MutableList<Map<String, Any?>>,
        visited: MutableSet<String>,
    ) {
        if (!visited.add(documentId)) return
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            documentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                if (idIndex < 0 || nameIndex < 0) continue
                val childId = cursor.getString(idIndex)
                val displayName = cursor.getString(nameIndex)?.trim().orEmpty()
                if (childId.isNullOrBlank() || displayName.isEmpty()) continue
                val relativePath = if (relativeParent.isEmpty()) {
                    displayName
                } else {
                    "$relativeParent/$displayName"
                }
                val mimeType = if (mimeIndex >= 0 && !cursor.isNull(mimeIndex)) {
                    cursor.getString(mimeIndex)
                } else {
                    null
                }
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    childId,
                )
                val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                if (isDirectory) {
                    collectLibraryDocuments(
                        treeUri = treeUri,
                        documentId = childId,
                        relativeParent = relativePath,
                        result = result,
                        visited = visited,
                    )
                } else {
                    val size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        cursor.getLong(sizeIndex).coerceAtLeast(0L)
                    } else {
                        null
                    }
                    val modified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) {
                        cursor.getLong(modifiedIndex).coerceAtLeast(0L)
                    } else {
                        null
                    }
                    result.add(
                        mapOf(
                            "treeUri" to treeUri.toString(),
                            "documentUri" to documentUri.toString(),
                            "relativePath" to relativePath,
                            "displayName" to displayName,
                            "sizeBytes" to size,
                            "modifiedAtEpochMs" to modified,
                            "isDirectory" to false,
                        ),
                    )
                }
            }
        }
    }

    private fun statLibraryDocument(
        treeUriString: String,
        documentUriString: String,
    ): Map<String, Any?> {
        val treeUri = Uri.parse(treeUriString)
        val documentUri = Uri.parse(documentUriString)
        ensureTreePermission(treeUri)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        return try {
            contentResolver.query(documentUri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    val size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        cursor.getLong(sizeIndex).coerceAtLeast(0L)
                    } else {
                        null
                    }
                    val modified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) {
                        cursor.getLong(modifiedIndex).coerceAtLeast(0L)
                    } else {
                        null
                    }
                    return@use mapOf(
                        "exists" to true,
                        "displayName" to if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                            cursor.getString(nameIndex)
                        } else {
                            null
                        },
                        "sizeBytes" to size,
                        "modifiedAtEpochMs" to modified,
                        "isDirectory" to (mimeIndex >= 0 &&
                            cursor.getString(mimeIndex) == DocumentsContract.Document.MIME_TYPE_DIR),
                    )
                }
                mapOf("exists" to false)
            }
                ?: mapOf("exists" to false)
        } catch (_: FileNotFoundException) {
            mapOf("exists" to false)
        } catch (error: IllegalArgumentException) {
            val message = error.message.orEmpty()
            if (message.contains("missing file", ignoreCase = true) ||
                message.contains("no such file", ignoreCase = true)
            ) {
                mapOf("exists" to false)
            } else {
                throw error
            }
        }
    }

    private fun copyLibraryDocumentToPath(
        treeUriString: String,
        documentUriString: String,
        destinationPath: String,
    ): Map<String, Any?> {
        val treeUri = Uri.parse(treeUriString)
        val documentUri = Uri.parse(documentUriString)
        ensureTreePermission(treeUri)
        val destination = File(destinationPath)
        destination.parentFile?.mkdirs()
        val temporary = File("$destinationPath.part")
        if (temporary.exists()) temporary.delete()
        try {
            val input = contentResolver.openInputStream(documentUri)
                ?: throw FileNotFoundException("Android source document could not be opened")
            input.use { source ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            if (destination.exists() && !destination.delete()) {
                throw IllegalStateException("destination file could not be replaced")
            }
            if (!temporary.renameTo(destination)) {
                throw IllegalStateException("materialized source could not be finalized")
            }
            return mapOf("sizeBytes" to destination.length())
        } catch (error: Exception) {
            if (temporary.exists()) temporary.delete()
            throw error
        }
    }

    private fun deleteLibraryDocument(
        treeUriString: String,
        documentUriString: String,
    ): Map<String, Any?> {
        val treeUri = Uri.parse(treeUriString)
        val documentUri = Uri.parse(documentUriString)
        ensureTreePermission(treeUri, requireWrite = true)
        try {
            val deleted = DocumentsContract.deleteDocument(contentResolver, documentUri)
            if (deleted) {
                return mapOf("deleted" to true, "deletedRows" to 1)
            }
            when (libraryDocumentExists(treeUri, documentUri)) {
                false -> return mapOf("deleted" to true, "deletedRows" to 0)
                true -> throw IllegalStateException("Android source document was not deleted")
                null -> throw IllegalStateException("Android source deletion could not be verified")
            }
        } catch (error: Exception) {
            // Some Android document providers delete the underlying document
            // and still throw UnsupportedOperationException.  Only accept
            // that provider outcome when a fresh capability-based query proves
            // that the document is gone; an unavailable verification remains
            // a failure so the import can be repaired safely.
            if (libraryDocumentExists(treeUri, documentUri) == false) {
                return mapOf(
                    "deleted" to true,
                    "deletedRows" to 0,
                    "providerWarning" to "delete outcome verified after provider error",
                )
            }
            throw error
        }
    }

    /**
     * Returns false only when a query completed and found no document, true
     * when it found a row, and null when the provider could not be queried.
     */
    private fun libraryDocumentExists(treeUri: Uri, documentUri: Uri): Boolean? {
        ensureTreePermission(treeUri)
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        return try {
            val cursor = contentResolver.query(documentUri, projection, null, null, null)
                ?: return null
            cursor.use { it.moveToFirst() }
        } catch (_: FileNotFoundException) {
            false
        } catch (error: IllegalArgumentException) {
            val message = error.message.orEmpty()
            if (message.contains("missing file", ignoreCase = true) ||
                message.contains("no such file", ignoreCase = true)
            ) {
                false
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == libraryTreeRequestCode) {
            val pending = pendingLibraryTreeResult
            pendingLibraryTreeResult = null
            if (pending != null) {
                if (resultCode != RESULT_OK || data?.data == null) {
                    pending.success(null)
                } else {
                    val uri = data.data!!
                    try {
                        val requestedFlags = data.flags and
                            (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        if (requestedFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) {
                            throw SecurityException("Android picker did not grant read access")
                        }
                        contentResolver.takePersistableUriPermission(uri, requestedFlags)
                        ensureTreePermission(uri)
                        pending.success(
                            mapOf(
                                "treeUri" to uri.toString(),
                                "displayName" to pickLibraryTreeDisplayName(uri),
                            ),
                        )
                    } catch (error: SecurityException) {
                        pending.error(
                            "PERMISSION_DENIED",
                            "Android folder permission could not be persisted.",
                            null,
                        )
                    }
                }
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun requestMediaReadAccess(result: MethodChannel.Result) {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingMediaReadPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "A media permission request is already in progress.",
                null,
            )
            return
        }
        pendingMediaReadPermissionResult = result
        requestPermissions(arrayOf(permission), mediaReadPermissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == mediaReadPermissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingMediaReadPermissionResult?.success(granted)
            pendingMediaReadPermissionResult = null
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
