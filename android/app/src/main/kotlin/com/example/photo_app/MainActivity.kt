package com.example.photo_app

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val mediaStoreChannel = "photo_app/media_store"
    private val transferChannel = "photo_app/background_transfer"
    private val downloadChannel = "photo_app/background_download"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToMediaStore") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val suppliedMimeType = call.argument<String>("mimeType")
                if (path == null || name == null) {
                    result.error("INVALID_ARGUMENT", "Missing media information", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(saveToMediaStore(File(path), name, resolveMimeType(name, suppliedMimeType)))
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, transferChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "enqueueMediaBatch") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val token = call.argument<String>("token") ?: throw IllegalArgumentException("Missing token")
                    val refreshToken = call.argument<String>("refreshToken") ?: throw IllegalArgumentException("Missing refresh token")
                    val baseUrl = call.argument<String>("baseUrl") ?: throw IllegalArgumentException("Missing base URL")
                    val albumId = call.argument<Int>("albumId") ?: -1
                    val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                    require(items.isNotEmpty()) { "No media selected" }

                    val batchId = UUID.randomUUID().toString()
                    val data = Data.Builder()
                        .putString(MediaUploadWorker.KEY_BATCH_ID, batchId)
                        .putString(MediaUploadWorker.KEY_TOKEN, token)
                        .putString(MediaUploadWorker.KEY_REFRESH_TOKEN, refreshToken)
                        .putString(MediaUploadWorker.KEY_BASE_URL, baseUrl)
                        .putInt(MediaUploadWorker.KEY_ALBUM_ID, albumId)
                        .putString(MediaUploadWorker.KEY_ITEMS_JSON, itemsToJson(items))
                        .build()

                    val request = OneTimeWorkRequestBuilder<MediaUploadWorker>()
                        .setInputData(data)
                        .addTag(batchId)
                        .build()

                    val prefs = getSharedPreferences(MediaUploadWorker.PREFS, MODE_PRIVATE)
                    prefs.edit()
                        .putInt("${batchId}_total", items.size)
                        .putInt("${batchId}_completed", 0)
                        .putInt("${batchId}_failed", 0)
                        .apply()

                    WorkManager.getInstance(applicationContext).enqueue(request)
                    result.success(batchId)
                } catch (e: Exception) {
                    result.error("QUEUE_FAILED", e.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "enqueueDownload") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val token = call.argument<String>("token") ?: throw IllegalArgumentException("Missing token")
                    val refreshToken = call.argument<String>("refreshToken") ?: throw IllegalArgumentException("Missing refresh token")
                    val baseUrl = call.argument<String>("baseUrl") ?: throw IllegalArgumentException("Missing base URL")
                    val photoId = call.argument<Int>("photoId") ?: throw IllegalArgumentException("Missing photo ID")
                    val filename = call.argument<String>("filename") ?: "photo"
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val batchId = UUID.randomUUID().toString()
                    val data = Data.Builder()
                        .putString(MediaDownloadWorker.KEY_BATCH_ID, batchId)
                        .putString(MediaDownloadWorker.KEY_TOKEN, token)
                        .putString(MediaDownloadWorker.KEY_REFRESH_TOKEN, refreshToken)
                        .putString(MediaDownloadWorker.KEY_BASE_URL, baseUrl)
                        .putInt(MediaDownloadWorker.KEY_PHOTO_ID, photoId)
                        .putString(MediaDownloadWorker.KEY_FILENAME, filename)
                        .putString(MediaDownloadWorker.KEY_MIME_TYPE, mimeType)
                        .build()
                    val request = OneTimeWorkRequestBuilder<MediaDownloadWorker>()
                        .setInputData(data)
                        .addTag(batchId)
                        .build()
                    WorkManager.getInstance(applicationContext).enqueue(request)
                    result.success(batchId)
                } catch (e: Exception) {
                    result.error("QUEUE_FAILED", e.message, null)
                }
            }
    }

    private fun itemsToJson(items: List<Map<String, Any?>>): String {
        val array = org.json.JSONArray()
        for (item in items) {
            val objectJson = org.json.JSONObject()
            objectJson.put("path", item["path"] as? String ?: "")
            objectJson.put("filename", item["filename"] as? String ?: "media")
            objectJson.put("type", item["type"] as? String ?: MediaUploadWorker.TYPE_PHOTO)
            array.put(objectJson)
        }
        return array.toString()
    }

    private fun saveToMediaStore(file: File, name: String, mimeType: String): String {
        require(file.exists()) { "Downloaded file does not exist" }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) throw IllegalStateException("Saving to device gallery requires Android 10 or newer")
        val resolver = contentResolver
        val isVideo = mimeType.startsWith("video/")
        val collection = if (isVideo) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (isVideo) "Movies/PhotoApp" else "Pictures/PhotoApp")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IllegalStateException("Unable to create media entry")
        try {
            resolver.openOutputStream(uri)?.use { output -> file.inputStream().use { input -> input.copyTo(output) } } ?: throw IllegalStateException("Unable to open media output")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun resolveMimeType(name: String, supplied: String?): String {
        val mime = supplied?.trim()?.lowercase()
        if (!mime.isNullOrBlank() && mime != "application/octet-stream" && (mime.startsWith("image/") || mime.startsWith("video/"))) return mime
        return when (name.substringAfterLast('.', "").lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            "mp4" -> "video/mp4"
            "m4v" -> "video/x-m4v"
            "mov" -> "video/quicktime"
            "webm" -> "video/webm"
            "3gp" -> "video/3gpp"
            else -> "application/octet-stream"
        }
    }
}
