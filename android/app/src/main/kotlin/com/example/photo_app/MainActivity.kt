package com.example.photo_app

import android.content.ContentValues
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
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
    private val videoChannel = "photo_app/video_transcoder"
    private val transferChannel = "photo_app/background_transfer"

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
                    val baseUrl = call.argument<String>("baseUrl") ?: throw IllegalArgumentException("Missing base URL")
                    val albumId = call.argument<Int>("albumId") ?: -1
                    val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                    require(items.isNotEmpty()) { "No media selected" }

                    val batchId = UUID.randomUUID().toString()
                    val prefs = getSharedPreferences(MediaUploadWorker.PREFS, MODE_PRIVATE)
                    prefs.edit()
                        .putInt("${batchId}_total", items.size)
                        .putInt("${batchId}_completed", 0)
                        .putInt("${batchId}_failed", 0)
                        .apply()

                    val workManager = WorkManager.getInstance(applicationContext)
                    for (item in items) {
                        val path = item["path"] as? String ?: throw IllegalArgumentException("Missing media path")
                        val filename = item["filename"] as? String ?: File(path).name
                        val type = item["type"] as? String ?: MediaUploadWorker.TYPE_PHOTO
                        val data = Data.Builder()
                            .putString(MediaUploadWorker.KEY_BATCH_ID, batchId)
                            .putString(MediaUploadWorker.KEY_TYPE, type)
                            .putString(MediaUploadWorker.KEY_TOKEN, token)
                            .putString(MediaUploadWorker.KEY_BASE_URL, baseUrl)
                            .putInt(MediaUploadWorker.KEY_ALBUM_ID, albumId)
                            .putString(MediaUploadWorker.KEY_ORIGINAL_PATH, path)
                            .putString(MediaUploadWorker.KEY_ORIGINAL_FILENAME, filename)
                            .build()

                        val request = OneTimeWorkRequestBuilder<MediaUploadWorker>()
                            .setInputData(data)
                            .addTag(batchId)
                            .build()
                        workManager.enqueue(request)
                    }
                    result.success(batchId)
                } catch (e: Exception) {
                    result.error("QUEUE_FAILED", e.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "createPlaybackVideo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val inputPath = call.argument<String>("inputPath")
                if (inputPath == null) {
                    result.error("INVALID_ARGUMENT", "Missing input video path", null)
                    return@setMethodCallHandler
                }
                try {
                    createPlaybackVideo(inputPath, result)
                } catch (e: Exception) {
                    result.error("TRANSCODE_FAILED", e.message, null)
                }
            }
    }

    @OptIn(UnstableApi::class)
    private fun createPlaybackVideo(inputPath: String, result: MethodChannel.Result) {
        val inputFile = File(inputPath)
        require(inputFile.exists()) { "Input video does not exist" }
        val outputFile = File(cacheDir, "playback-${System.currentTimeMillis()}.mp4")
        if (outputFile.exists()) outputFile.delete()
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(inputPath)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val editedBuilder = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(inputFile)))
            if (width > 1920 || height > 1920) {
                val scale = minOf(1920f / width, 1920f / height)
                editedBuilder.setEffects(Effects(emptyList(), listOf(ScaleAndRotateTransformation.Builder().setScale(scale, scale).build())))
            }
            val transformer = Transformer.Builder(this)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setPortraitEncodingEnabled(true)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                        if (!outputFile.isFile || outputFile.length() == 0L) {
                            result.error("TRANSCODE_FAILED", "Playback output is empty", null)
                            return
                        }
                        result.success(outputFile.absolutePath)
                    }
                    override fun onError(composition: androidx.media3.transformer.Composition, exportResult: ExportResult, exportException: ExportException) {
                        if (outputFile.exists()) outputFile.delete()
                        result.error("TRANSCODE_FAILED", exportException.message, null)
                    }
                }).build()
            transformer.start(editedBuilder.build(), outputFile.absolutePath)
        } finally {
            retriever.release()
        }
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
