package com.example.photo_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class MediaUploadWorker(appContext: Context, workerParams: WorkerParameters) : CoroutineWorker(appContext, workerParams) {
    private val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override suspend fun getForegroundInfo(): ForegroundInfo {
        ensureNotificationChannel()
        return createForegroundInfo(buildNotification("Preparing upload…", 0, totalItems(), true))
    }

    override suspend fun doWork(): Result {
        val batchId = inputData.getString(KEY_BATCH_ID) ?: return Result.failure()
        val token = inputData.getString(KEY_TOKEN) ?: return Result.failure()
        val baseUrl = inputData.getString(KEY_BASE_URL) ?: return Result.failure()
        val albumId = inputData.getInt(KEY_ALBUM_ID, -1)
        val items = JSONArray(inputData.getString(KEY_ITEMS_JSON) ?: "[]")
        if (items.length() == 0) return Result.failure()

        ensureNotificationChannel()
        setForeground(createForegroundInfo(buildNotification("Preparing upload…", 0, items.length(), true)))

        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val total = items.length()
        prefs.edit().putInt("${batchId}_total", total).apply()

        return try {
            for (index in 0 until total) {
                if (isStopped) return Result.retry()
                if (prefs.getBoolean("${batchId}_item_$index", false)) continue

                val item = items.getJSONObject(index)
                val path = item.optString("path")
                val filename = item.optString("filename", File(path).name)
                val type = item.optString("type", TYPE_PHOTO)

                if (type == TYPE_VIDEO) {
                    updateBatchNotification(batchId, "Preparing video ${index + 1} of $total")
                    val playbackPath = transcodeVideo(path)
                    try {
                        updateBatchNotification(batchId, "Uploading ${index + 1} of $total")
                        val response = uploadVideo(baseUrl, token, path, filename, playbackPath)
                        linkAlbumIfNeeded(baseUrl, token, albumId, response)
                    } finally {
                        File(playbackPath).delete()
                    }
                } else {
                    updateBatchNotification(batchId, "Uploading ${index + 1} of $total")
                    val response = uploadPhoto(baseUrl, token, path, filename)
                    linkAlbumIfNeeded(baseUrl, token, albumId, response)
                }

                prefs.edit().putBoolean("${batchId}_item_$index", true).putInt("${batchId}_completed", index + 1).apply()
                File(path).delete()
                updateBatchNotification(batchId, if (index + 1 == total) "Upload complete" else "Uploading ${index + 1} of $total")
            }

            notificationManager.notify(NOTIFICATION_ID, buildNotification("Upload complete", total, total, false))
            cleanupBatchState(batchId, total)
            Result.success()
        } catch (error: Throwable) {
            Log.e(TAG, "Media transfer failed (attempt ${runAttemptCount + 1})", error)
            val completed = prefs.getInt("${batchId}_completed", 0)
            val message = error.message?.replace('\n', ' ')?.take(90) ?: error.javaClass.simpleName
            if (error is ExportException || error is IllegalArgumentException || error.message?.contains("Video file not found", true) == true || error.message?.contains("video dimensions", true) == true) {
                notificationManager.notify(NOTIFICATION_ID, buildNotification("Video preparation failed", completed, total, false, message))
                cleanupBatchState(batchId, total)
                return Result.failure()
            }
            if (runAttemptCount < 2) {
                notificationManager.notify(NOTIFICATION_ID, buildNotification("Retrying upload…", completed, total, false, message))
                Result.retry()
            } else {
                notificationManager.notify(NOTIFICATION_ID, buildNotification("Upload finished with errors", completed, total, false, message))
                Result.failure()
            }
        }
    }

    private fun createForegroundInfo(notification: android.app.Notification): ForegroundInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
        ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Media transfers", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Background photo and video uploads"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun totalItems(): Int = runCatching { JSONArray(inputData.getString(KEY_ITEMS_JSON) ?: "[]").length() }.getOrDefault(0)

    @OptIn(UnstableApi::class)
    private suspend fun transcodeVideo(inputPath: String): String = suspendCancellableCoroutine { continuation ->
        val inputFile = File(inputPath)
        require(inputFile.isFile) { "Video file not found" }
        val outputFile = File(applicationContext.cacheDir, "playback-${UUID.randomUUID()}.mp4")
        val retriever = android.media.MediaMetadataRetriever()
        try {
            retriever.setDataSource(inputPath)
            val width = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            require(width > 0 && height > 0) { "Unable to read video dimensions" }

            val builder = EditedMediaItem.Builder(MediaItem.fromUri(android.net.Uri.fromFile(inputFile)))
            if (width > 1920 || height > 1920) {
                val scale = minOf(1920f / width, 1920f / height)
                builder.setEffects(Effects(emptyList(), listOf(ScaleAndRotateTransformation.Builder().setScale(scale, scale).build())))
            }

            Log.i(TAG, "Starting video preparation: $inputPath (${width}x${height}) -> ${outputFile.absolutePath}")
            val transformer = Transformer.Builder(applicationContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setPortraitEncodingEnabled(true)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                        Log.i(TAG, "Video preparation completed: ${outputFile.length()} bytes")
                        if (outputFile.isFile && outputFile.length() > 0L) continuation.resume(outputFile.absolutePath)
                        else continuation.resumeWithException(Exception("Playback output is empty"))
                    }
                    override fun onError(composition: androidx.media3.transformer.Composition, exportResult: ExportResult, exportException: ExportException) {
                        Log.e(TAG, "Video preparation failed", exportException)
                        outputFile.delete()
                        if (continuation.isActive) continuation.resumeWithException(exportException)
                    }
                }).build()
            transformer.start(builder.build(), outputFile.absolutePath)
            continuation.invokeOnCancellation { transformer.cancel() }
        } catch (error: Throwable) {
            Log.e(TAG, "Could not start video preparation", error)
            outputFile.delete()
            if (continuation.isActive) continuation.resumeWithException(error)
        } finally {
            retriever.release()
        }
    }

    private suspend fun uploadPhoto(baseUrl: String, token: String, path: String, filename: String): String = withContext(Dispatchers.IO) {
        multipartPost("$baseUrl/photos/upload", token, listOf(Triple("file", File(path), filename)))
    }

    private suspend fun uploadVideo(baseUrl: String, token: String, originalPath: String, originalFilename: String, playbackPath: String): String = withContext(Dispatchers.IO) {
        multipartPost("$baseUrl/photos/upload-video", token, listOf(Triple("original_file", File(originalPath), originalFilename), Triple("playback_file", File(playbackPath), "playback.mp4")))
    }

    private suspend fun linkAlbumIfNeeded(baseUrl: String, token: String, albumId: Int, response: String) = withContext(Dispatchers.IO) {
        if (albumId < 0) return@withContext
        val photoId = JSONObject(response).optInt("id", -1)
        if (photoId < 0) return@withContext
        val connection = (URL("$baseUrl/albums/$albumId/photos/$photoId").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 30_000
            readTimeout = 30_000
            setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            if (connection.responseCode !in 200..299) throw Exception("Album link failed: ${connection.responseCode}")
        } finally {
            connection.disconnect()
        }
    }

    private fun multipartPost(url: String, token: String, files: List<Triple<String, File, String>>): String {
        val boundary = "----PhotoApp${UUID.randomUUID()}"
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 30_000
            readTimeout = 300_000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }
        try {
            connection.outputStream.use { output ->
                for ((field, file, filename) in files) {
                    require(file.isFile) { "Upload file not found: ${file.absolutePath}" }
                    output.write("--$boundary\r\n".toByteArray())
                    output.write("Content-Disposition: form-data; name=\"$field\"; filename=\"$filename\"\r\n".toByteArray())
                    output.write("Content-Type: application/octet-stream\r\n\r\n".toByteArray())
                    file.inputStream().use { input ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                        }
                    }
                    output.write("\r\n".toByteArray())
                }
                output.write("--$boundary--\r\n".toByteArray())
            }
            val responseCode = connection.responseCode
            val response = if (responseCode in 200..299) connection.inputStream.bufferedReader().readText() else connection.errorStream?.bufferedReader()?.readText().orEmpty()
            if (responseCode !in 200..299) throw Exception("Upload failed ($responseCode): $response")
            return response
        } finally {
            connection.disconnect()
        }
    }

    private fun updateBatchNotification(batchId: String, text: String) {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val completed = prefs.getInt("${batchId}_completed", 0)
        val total = prefs.getInt("${batchId}_total", 1)
        notificationManager.notify(NOTIFICATION_ID, buildNotification(text, completed, total, true))
    }

    private fun buildNotification(text: String, completed: Int, total: Int, ongoing: Boolean, detail: String? = null) = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
        .setSmallIcon(com.example.photo_app.R.mipmap.ic_launcher)
        .setContentTitle("Photo Storage")
        .setContentText(if (detail.isNullOrBlank()) text else "$text: $detail")
        .setOngoing(ongoing)
        .setAutoCancel(!ongoing)
        .setOnlyAlertOnce(true)
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        .setProgress(if (total > 0) total else 0, completed.coerceAtMost(total), false)
        .build()

    private fun cleanupBatchState(batchId: String, total: Int) {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for (index in 0 until total) editor.remove("${batchId}_item_$index")
        editor.remove("${batchId}_total").remove("${batchId}_completed").remove("${batchId}_failed").apply()
    }

    companion object {
        private const val TAG = "PhotoAppTransfer"
        const val KEY_BATCH_ID = "batchId"
        const val KEY_TOKEN = "token"
        const val KEY_BASE_URL = "baseUrl"
        const val KEY_ALBUM_ID = "albumId"
        const val KEY_ITEMS_JSON = "itemsJson"
        const val TYPE_VIDEO = "video"
        const val TYPE_PHOTO = "photo"
        const val NOTIFICATION_ID = 4101
        const val CHANNEL_ID = "media_transfer"
        const val PREFS = "media_transfer_state"
    }
}
