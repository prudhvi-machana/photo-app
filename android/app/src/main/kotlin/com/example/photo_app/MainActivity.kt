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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val mediaStoreChannel = "photo_app/media_store"
    private val videoChannel = "photo_app/video_transcoder"

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
                    result.success(
                        saveToMediaStore(
                            File(path),
                            name,
                            resolveMimeType(name, suppliedMimeType),
                        )
                    )
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
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
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0

            val mediaItem = MediaItem.fromUri(Uri.fromFile(inputFile))
            val editedBuilder = EditedMediaItem.Builder(mediaItem)

            if (width > 1920 || height > 1920) {
                val scale = minOf(1920f / width, 1920f / height)
                val effect = ScaleAndRotateTransformation.Builder()
                    .setScale(scale, scale)
                    .build()

                editedBuilder.setEffects(
                    Effects(
                        emptyList(),
                        listOf(effect),
                    )
                )
            }

            val transformer = Transformer.Builder(this)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setPortraitEncodingEnabled(true)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(
                        composition: androidx.media3.transformer.Composition,
                        exportResult: ExportResult,
                    ) {
                        if (!outputFile.isFile || outputFile.length() == 0L) {
                            result.error("TRANSCODE_FAILED", "Playback output is empty", null)
                            return
                        }
                        result.success(outputFile.absolutePath)
                    }

                    override fun onError(
                        composition: androidx.media3.transformer.Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        if (outputFile.exists()) outputFile.delete()
                        result.error("TRANSCODE_FAILED", exportException.message, null)
                    }
                })
                .build()

            transformer.start(editedBuilder.build(), outputFile.absolutePath)
        } finally {
            retriever.release()
        }
    }

    private fun saveToMediaStore(file: File, name: String, mimeType: String): String {
        require(file.exists()) { "Downloaded file does not exist" }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("Saving to device gallery requires Android 10 or newer")
        }

        val resolver = contentResolver
        val isVideo = mimeType.startsWith("video/")
        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                if (isVideo) "Movies/PhotoApp" else "Pictures/PhotoApp"
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("Unable to create media entry")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Unable to open media output")

            val completed = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, completed, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun resolveMimeType(name: String, supplied: String?): String {
        val mime = supplied?.trim()?.lowercase()
        if (!mime.isNullOrBlank() && mime != "application/octet-stream" &&
            (mime.startsWith("image/") || mime.startsWith("video/"))) {
            return mime
        }

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
