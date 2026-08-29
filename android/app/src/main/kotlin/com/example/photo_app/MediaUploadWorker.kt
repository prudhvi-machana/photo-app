package com.example.photo_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class MediaUploadWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    private val notificationManager =
        applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override suspend fun getForegroundInfo(): ForegroundInfo {
        ensureNotificationChannel()
        return ForegroundInfo(NOTIFICATION_ID, buildNotification("Preparing media…", 0, 0, true))
    }

    override suspend fun doWork(): Result {
        val batchId = inputData.getString(KEY_BATCH_ID) ?: return Result.failure()
        val type = inputData.getString(KEY_TYPE) ?: return Result.failure()
        val token = inputData.getString(KEY_TOKEN) ?: return Result.failure()
        val baseUrl = inputData.getString(KEY_BASE_URL) ?: return Result.failure()
        val originalPath = inputData.getString(KEY_ORIGINAL_PATH) ?: return Result.failure()
        val originalFilename = inputData.getString(KEY_ORIGINAL_FILENAME) ?: "media"

        setForeground(getForegroundInfo())
        ensureNotificationChannel()

        return try {
            if (type == TYPE_VIDEO) {
                updateBatchNotification(batchId, "Preparing $originalFilename…")
                val playbackPath = transcodeVideo(originalPath)
                try {
                    uploadVideo(baseUrl, token, originalPath, originalFilename, playbackPath)
                } finally {
                    File(playbackPath).delete()
                }
            } else {
                updateBatchNotification(batchId, "Uploading $originalFilename…")
                uploadPhoto(baseUrl, token, originalPath, originalFilename)
            }

            markCompleted(batchId)
            Result.success()
        } catch (error: Throwable) {
            if (runAttemptCount < 2) {
                Result.retry()
            } else {
                markFailed(batchId)
                Result.failure()
            }
        }
    }

    @OptIn(UnstableApi::class)
    private suspend fun transcodeVideo(inputPath: String): String =
        suspendCancellableCoroutine { continuation ->
            val inputFile = File(inputPath)
            require(inputFile.isFile) { "Video file not found" }

            val outputFile = File(applicationContext.cacheDir, "playback-${UUID.randomUUID()}.mp4")
            val retriever = android.media.MediaMetadataRetriever()
            try {
                retriever.setDataSource(inputPath)
                val width = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                val height = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                val builder = EditedMediaItem.Builder(MediaItem.fromUri(android.net.Uri.fromFile(inputFile)))

                if (width > 1920 || height > 1920) {
                    val scale = minOf(1920f / width, 1920f / height)
                    val effect = ScaleAndRotateTransformation.Builder().setScale(scale, scale).build()
                    builder.setEffects(Effects(emptyList(), listOf(effect)))
                }

                val transformer = Transformer.Builder(applicationContext)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setPortraitEncodingEnabled(true)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                            if (outputFile.isFile && outputFile.length() > 0L) {
                                continuation.resume(outputFile.absolutePath)
                            } else {
                                continuation.resumeWithException(Exception("Playback output is empty"))
                            }
                        }

                        override fun onError(composition: androidx.media3.transformer.Composition, exportResult: ExportResult, exportException: ExportException) {
                            outputFile.delete()
                            continuation.resumeWithException(exportException)
                        }
                    })
                    .build()

                transformer.start(builder.build(), outputFile.absolutePath)
                continuation.invokeOnCancellation { transformer.cancel() }
            } finally {
                retriever.release()
            }
        }

    private suspend fun uploadPhoto(baseUrl: String, token: String, path: String, filename: String) = withContext(Dispatchers.IO) {
        multipartPost("$baseUrl/photos/upload", token, listOf(Triple("file", File(path), filename)))
    }

    private suspend fun uploadVideo(baseUrl: String, token: String, originalPath: String, originalFilename: String, playbackPath: String) = withContext(Dispatchers.IO) {
        multipartPost(
            "$baseUrl/photos/upload-video",
            token,
            listOf(
                Triple("original_file", File(originalPath), originalFilename),
                Triple("playback_file", File(playbackPath), "playback.mp4"),
            ),
        )
    }

    private fun multipartPost(url: String, token: String, files: List<Triple<String, File, String>>) {
        val boundary = "----PhotoApp${UUID.randomUUID()}"
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 30_000
            readTimeout = 300_000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }

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
        if (responseCode !in 200..299) {
            val body = runCatching { connection.errorStream?.bufferedReader()?.readText() }.getOrNull()
            throw Exception("Upload failed ($responseCode): ${body ?: "unknown error"}")
        }
        connection.disconnect()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Media transfers", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    private fun buildNotification(text: String, completed: Int, total: Int, ongoing: Boolean) =
        NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(com.example.photo_app.R.mipmap.ic_launcher)
            .setContentTitle("Photo Storage")
            .setContentText(text)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setOnlyAlertOnce(true)
            .setProgress(if (total > 0) total else 0, completed, false)
            .build()

    private fun updateBatchNotification(batchId: String, text: String) {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val completed = prefs.getInt("${batchId}_completed", 0)
        val total = prefs.getInt("${batchId}_total", 1)
        notificationManager.notify(NOTIFICATION_ID, buildNotification(text, completed, total, true))
    }

    private fun markCompleted(batchId: String) {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val completed = prefs.getInt("${batchId}_completed", 0) + 1
        val total = prefs.getInt("${batchId}_total", 1)
        prefs.edit().putInt("${batchId}_completed", completed).apply()
        notificationManager.notify(
            NOTIFICATION_ID,
            buildNotification(if (completed >= total) "Upload complete" else "Uploading $completed of $total", completed, total, completed < total),
        )
    }

    private fun markFailed(batchId: String) {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val completed = prefs.getInt("${batchId}_completed", 0)
        val total = prefs.getInt("${batchId}_total", 1)
        prefs.edit().putInt("${batchId}_failed", prefs.getInt("${batchId}_failed", 0) + 1).apply()
        notificationManager.notify(NOTIFICATION_ID, buildNotification("Upload finished with errors", completed, total, false))
    }

    companion object {
        const val KEY_BATCH_ID = "batchId"
        const val KEY_TYPE = "type"
        const val KEY_TOKEN = "token"
        const val KEY_BASE_URL = "baseUrl"
        const val KEY_ORIGINAL_PATH = "originalPath"
        const val KEY_ORIGINAL_FILENAME = "originalFilename"
        const val TYPE_VIDEO = "video"
        const val TYPE_PHOTO = "photo"
        const val NOTIFICATION_ID = 4101
        const val CHANNEL_ID = "media_transfer"
        const val PREFS = "media_transfer_state"
    }
}
