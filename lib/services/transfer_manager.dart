import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class TransferManager {
  static const String mediaUploadGroup = 'mediaUploads';
  static const String mediaUploadNotificationId = 'mediaUploadBatch';

  static Future<void> initialize() async {
    final downloader = FileDownloader();

    downloader.configureNotificationForGroup(
      mediaUploadGroup,
      running: const TaskNotification(
        'Uploading {numFinished} of {numTotal}',
        'Photo Storage',
      ),
      complete: const TaskNotification(
        'Upload complete',
        'All selected media uploaded',
      ),
      error: const TaskNotification(
        'Upload finished with errors',
        'Some selected media could not be uploaded',
      ),
      canceled: const TaskNotification(
        'Upload canceled',
        'Some selected media was canceled',
      ),
      progressBar: true,
      groupNotificationId: mediaUploadNotificationId,
    );

    downloader.registerCallbacks(
      group: mediaUploadGroup,
      taskStatusCallback: _onStatus,
    );

    await downloader.start(
      doTrackTasks: true,
      doRescheduleKilledTasks: true,
    );
  }

  static Future<bool> enqueuePhotoUpload({
    required String filePath,
    required String filename,
    required String token,
    int? albumId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Selected file is no longer available');
    }

    final (baseDirectory, directory, taskFilename) =
        await Task.split(filePath: filePath);

    final metadata = jsonEncode({
      'albumId': albumId,
    });

    final task = UploadTask(
      url: '${ApiConfig.baseUrl}/photos/upload',
      baseDirectory: baseDirectory,
      directory: directory,
      filename: taskFilename,
      headers: {
        'Authorization': 'Bearer $token',
      },
      fileField: 'file',
      group: mediaUploadGroup,
      updates: Updates.statusAndProgress,
      retries: 3,
      displayName: filename,
      metaData: metadata,
    );

    return FileDownloader().enqueue(task);
  }

  static Future<bool> enqueueVideoUpload({
    required String originalPath,
    required String originalFilename,
    required String playbackPath,
    required String token,
    int? albumId,
  }) async {
    final original = File(originalPath);
    final playback = File(playbackPath);

    if (!await original.exists()) {
      throw Exception('Original video is no longer available');
    }
    if (!await playback.exists()) {
      throw Exception('Playback video is no longer available');
    }

    final metadata = jsonEncode({
      'albumId': albumId,
      'playbackPath': playbackPath,
    });

    final task = MultiUploadTask(
      url: '${ApiConfig.baseUrl}/photos/upload-video',
      files: [
        ('original_file', originalPath),
        ('playback_file', playbackPath),
      ],
      headers: {
        'Authorization': 'Bearer $token',
      },
      group: mediaUploadGroup,
      updates: Updates.statusAndProgress,
      retries: 3,
      displayName: originalFilename,
      metaData: metadata,
    );

    return FileDownloader().enqueue(task);
  }

  static Future<void> _onStatus(TaskStatusUpdate update) async {
    if (update.status != TaskStatus.complete) {
      return;
    }

    final rawMetadata = update.task.metaData;
    if (rawMetadata.isEmpty || update.responseBody == null) {
      await _cleanupPlaybackFile(rawMetadata);
      return;
    }

    try {
      final metadata = jsonDecode(rawMetadata) as Map<String, dynamic>;
      final albumId = metadata['albumId'];
      final body = jsonDecode(update.responseBody!) as Map<String, dynamic>;
      final photoId = body['id'];

      if (albumId is int && photoId is int) {
        final authorization = update.task.headers['Authorization'];
        if (authorization != null && authorization.isNotEmpty) {
          final response = await http.post(
            Uri.parse('${ApiConfig.baseUrl}/albums/$albumId/photos/$photoId'),
            headers: {'Authorization': authorization},
          );

          if (response.statusCode != 200 && response.statusCode != 201) {
            stderr.writeln(
              'Background transfer: failed to add photo $photoId to album $albumId: '
              '${response.statusCode}',
            );
          }
        }
      }

      await _cleanupPlaybackFile(rawMetadata);
    } catch (error) {
      stderr.writeln('Background transfer completion handling failed: $error');
    }
  }

  static Future<void> _cleanupPlaybackFile(String rawMetadata) async {
    if (rawMetadata.isEmpty) return;

    try {
      final metadata = jsonDecode(rawMetadata) as Map<String, dynamic>;
      final playbackPath = metadata['playbackPath'];
      if (playbackPath is String && playbackPath.isNotEmpty) {
        final file = File(playbackPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      // Temporary playback cleanup must never affect transfer completion.
    }
  }
}
