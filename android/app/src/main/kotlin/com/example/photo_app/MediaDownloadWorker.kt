package com.example.photo_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class MediaDownloadWorker(appContext: Context, workerParams: WorkerParameters) : CoroutineWorker(appContext, workerParams) {
    private val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override suspend fun getForegroundInfo(): ForegroundInfo {
        ensureChannel()
        return foreground(buildNotification("Preparing download…", 0, true))
    }

    override suspend fun doWork(): Result {
        val batchId = inputData.getString(KEY_BATCH_ID) ?: return Result.failure()
        var accessToken = inputData.getString(KEY_TOKEN) ?: return Result.failure()
        val refreshToken = inputData.getString(KEY_REFRESH_TOKEN) ?: return Result.failure()
        val baseUrl = inputData.getString(KEY_BASE_URL) ?: return Result.failure()
        val photoId = inputData.getInt(KEY_PHOTO_ID, -1)
        val filename = inputData.getString(KEY_FILENAME) ?: "photo"
        val mimeType = inputData.getString(KEY_MIME_TYPE) ?: "application/octet-stream"
        if (photoId < 0) return Result.failure()

        ensureChannel()
        setForeground(foreground(buildNotification("Downloading $filename", 0, true)))

        return try {
            val tempFile = File(applicationContext.cacheDir, "download-${UUID.randomUUID()}")
            try {
                try {
                    download(baseUrl, accessToken, photoId, tempFile, batchId, filename)
                } catch (_: UnauthorizedException) {
                    accessToken = refreshAccessToken(baseUrl, refreshToken)
                    download(baseUrl, accessToken, photoId, tempFile, batchId, filename)
                }

                saveToMediaStore(tempFile, filename, mimeType)
                notificationManager.notify(COMPLETION_NOTIFICATION_ID, buildNotification("Download complete", 100, false))
                Result.success()
            } finally {
                tempFile.delete()
            }
        } catch (error: Throwable) {
            val message = error.message?.replace('\n', ' ')?.take(100) ?: error.javaClass.simpleName
            notificationManager.notify(COMPLETION_NOTIFICATION_ID, buildNotification("Download failed: $message", 0, false))
            Result.failure()
        }
    }

    private suspend fun download(baseUrl: String, token: String, photoId: Int, output: File, batchId: String, filename: String) = withContext(Dispatchers.IO) {
        val connection = (URL("$baseUrl/photos/$photoId").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 30_000
            readTimeout = 300_000
            setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            val code = connection.responseCode
            if (code == HttpURLConnection.HTTP_UNAUTHORIZED) throw UnauthorizedException("Download unauthorized")
            if (code !in 200..299) throw Exception("Download failed ($code)")
            val total = connection.contentLengthLong
            var received = 0L
            var lastPercent = -1
            connection.inputStream.use { input ->
                output.outputStream().use { out ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        out.write(buffer, 0, read)
                        received += read
                        val percent = if (total > 0) ((received * 100L) / total).toInt().coerceIn(0, 100) else 0
                        if (percent != lastPercent) {
                            lastPercent = percent
                            notificationManager.notify(NOTIFICATION_ID, buildNotification("Downloading $filename", percent, true))
                        }
                    }
                }
            }
            notificationManager.notify(NOTIFICATION_ID, buildNotification("Saving $filename", 100, true))
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun refreshAccessToken(baseUrl: String, refreshToken: String): String = withContext(Dispatchers.IO) {
        val connection = (URL("$baseUrl/auth/refresh").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 30_000
            readTimeout = 30_000
            setRequestProperty("Content-Type", "application/json")
        }
        try {
            connection.outputStream.use { it.write(JSONObject().put("refresh_token", refreshToken).toString().toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val body = if (code in 200..299) connection.inputStream.bufferedReader().readText() else connection.errorStream?.bufferedReader()?.readText().orEmpty()
            if (code !in 200..299) throw Exception("Token refresh failed ($code)")
            val token = JSONObject(body).optString("access_token")
            if (token.isBlank()) throw Exception("Token refresh returned no access token")
            token
        } finally {
            connection.disconnect()
        }
    }

    private fun saveToMediaStore(file: File, name: String, mimeType: String) {
        require(file.isFile) { "Downloaded file is missing" }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) throw Exception("Gallery saving requires Android 10+")
        val isVideo = mimeType.startsWith("video/")
        val collection = if (isVideo) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (isVideo) "Movies/PhotoApp" else "Pictures/PhotoApp")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = applicationContext.contentResolver
        val uri = resolver.insert(collection, values) ?: throw Exception("Unable to create gallery entry")
        try {
            resolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output) } } ?: throw Exception("Unable to open gallery output")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun foreground(notification: android.app.Notification): ForegroundInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else ForegroundInfo(NOTIFICATION_ID, notification)

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Media downloads", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Background photo and video downloads"
                setShowBadge(false)
            })
        }
    }

    private fun buildNotification(text: String, percent: Int, ongoing: Boolean) = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
        .setSmallIcon(com.example.photo_app.R.mipmap.ic_launcher)
        .setContentTitle("Photo Storage")
        .setContentText(if (percent in 0..100 && ongoing) "$text — $percent%" else text)
        .setOngoing(ongoing)
        .setAutoCancel(!ongoing)
        .setOnlyAlertOnce(true)
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        .setProgress(100, percent.coerceIn(0, 100), false)
        .build()

    private class UnauthorizedException(message: String) : Exception(message)

    companion object {
        const val KEY_BATCH_ID = "batchId"
        const val KEY_TOKEN = "token"
        const val KEY_REFRESH_TOKEN = "refreshToken"
        const val KEY_BASE_URL = "baseUrl"
        const val KEY_PHOTO_ID = "photoId"
        const val KEY_FILENAME = "filename"
        const val KEY_MIME_TYPE = "mimeType"
        const val NOTIFICATION_ID = 4201
        const val COMPLETION_NOTIFICATION_ID = 4202
        const val CHANNEL_ID = "media_download"
    }
}
