package com.example.photo_app

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "photo_app/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
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
