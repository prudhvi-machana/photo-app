import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class TransferManager {
  static const String photoUploadGroup = 'photoUploads';

  static Future<void> initialize() async {
    final downloader = FileDownloader();

    downloader.configureNotificationForGroup(
      photoUploadGroup,
      running: const TaskNotification(
        'Uploading {displayName}',
        '{progress}',
      ),
      complete: const TaskNotification(
        'Upload complete',
        '{displayName}',
      ),
      error: const TaskNotification(
        'Upload failed',
        '{displayName}',
      ),
      canceled: const TaskNotification(
        'Upload canceled',
        '{displayName}',
      ),
      progressBar: true,
    );

    downloader.registerCallbacks(
      group: photoUploadGroup,
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
      group: photoUploadGroup,
      updates: Updates.statusAndProgress,
      retries: 3,
      displayName: filename,
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
      return;
    }

    try {
      final metadata = jsonDecode(rawMetadata) as Map<String, dynamic>;
      final albumId = metadata['albumId'];
      if (albumId is! int) {
        return;
      }

      final body = jsonDecode(update.responseBody!) as Map<String, dynamic>;
      final photoId = body['id'];
      if (photoId is! int) {
        return;
      }

      final authorization = update.task.headers?['Authorization'];
      if (authorization == null || authorization.isEmpty) {
        return;
      }

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/albums/$albumId/photos/$photoId',
        ),
        headers: {
          'Authorization': authorization,
        },
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        // The upload itself succeeded. Album association can be retried later.
        stderr.writeln(
          'Background transfer: failed to add photo $photoId to album $albumId: '
          '${response.statusCode}',
        );
      }
    } catch (error) {
      stderr.writeln('Background transfer completion handling failed: $error');
    }
  }
}
