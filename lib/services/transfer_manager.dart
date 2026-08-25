import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/photo.dart';
import 'api_config.dart';

class TransferItem {
  final String taskId;
  final String type;
  final String filename;
  double progress;
  TaskStatus status;
  String? error;

  TransferItem({
    required this.taskId,
    required this.type,
    required this.filename,
    this.progress = 0,
    this.status = TaskStatus.enqueued,
    this.error,
  });
}

class TransferManager extends ChangeNotifier {
  TransferManager._();

  static final TransferManager instance = TransferManager._();

  final FileDownloader _downloader = FileDownloader();
  final Map<String, TransferItem> _items = {};
  bool _initialized = false;

  List<TransferItem> get items => List.unmodifiable(_items.values);

  List<TransferItem> get activeItems => _items.values
      .where((item) => !item.status.isFinalState)
      .toList(growable: false);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _downloader.registerCallbacks(
      taskStatusCallback: _onStatus,
      taskProgressCallback: _onProgress,
    );

    await _downloader.trackTasks();
    await _downloader.resumeFromBackground();
  }

  void _onStatus(TaskStatusUpdate update) {
    final task = update.task;
    final type = task is UploadTask ? 'upload' : 'download';
    final filename = task.displayName.isNotEmpty
        ? task.displayName
        : task.filename;

    final item = _items.putIfAbsent(
      task.taskId,
      () => TransferItem(
        taskId: task.taskId,
        type: type,
        filename: filename,
      ),
    );

    item.status = update.status;
    if (update.status.isFinalState && update.exception != null) {
      item.error = update.exception.toString();
    }
    notifyListeners();
  }

  void _onProgress(TaskProgressUpdate update) {
    final task = update.task;
    final type = task is UploadTask ? 'upload' : 'download';
    final filename = task.displayName.isNotEmpty
        ? task.displayName
        : task.filename;

    final item = _items.putIfAbsent(
      task.taskId,
      () => TransferItem(
        taskId: task.taskId,
        type: type,
        filename: filename,
      ),
    );

    item.progress = update.progress.clamp(0.0, 1.0);
    notifyListeners();
  }

  Future<bool> enqueueUpload({
    required String path,
    required String filename,
    required String token,
    int? albumId,
    String? mimeType,
  }) async {
    await initialize();

    final task = UploadTask.fromFile(
      file: File(path),
      url: '${ApiConfig.baseUrl}/photos/upload',
      headers: {'Authorization': 'Bearer $token'},
      mimeType: mimeType,
      fields: albumId == null ? null : {'album_id': albumId.toString()},
      displayName: filename,
      updates: Updates.statusAndProgress,
      retries: 3,
      priority: 0,
      allowPause: true,
      group: 'media-transfers',
    );

    _items[task.taskId] = TransferItem(
      taskId: task.taskId,
      type: 'upload',
      filename: filename,
    );
    notifyListeners();

    return _downloader.enqueue(task);
  }

  Future<bool> enqueueDownload({
    required Photo photo,
    required String token,
  }) async {
    await initialize();

    final isVideo = photo.mimeType.toLowerCase().startsWith('video/') ||
        RegExp(r'\.(mp4|mov|m4v|webm|3gp)$', caseSensitive: false)
            .hasMatch(photo.originalFilename);

    final task = DownloadTask(
      url: '${ApiConfig.baseUrl}/photos/${photo.id}',
      headers: {'Authorization': 'Bearer $token'},
      filename: photo.originalFilename,
      directory: 'PhotoAppTransfers',
      baseDirectory: BaseDirectory.applicationSupport,
      displayName: photo.originalFilename,
      updates: Updates.statusAndProgress,
      retries: 3,
      priority: 0,
      allowPause: true,
      group: 'media-transfers',
    );

    _items[task.taskId] = TransferItem(
      taskId: task.taskId,
      type: 'download',
      filename: photo.originalFilename,
    );
    notifyListeners();

    final enqueued = await _downloader.enqueue(task);

    if (enqueued) {
      _watchDownloadCompletion(task, isVideo);
    }
    return enqueued;
  }

  Future<void> _watchDownloadCompletion(
    DownloadTask task,
    bool isVideo,
  ) async {
    while (true) {
      final record = await _downloader.database.recordForId(task.taskId);
      if (record == null || !record.status.isFinalState) {
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }

      if (record.status == TaskStatus.complete) {
        try {
          await _downloader.moveToSharedStorage(
            record.task,
            isVideo ? SharedStorage.video : SharedStorage.images,
            directory: isVideo ? 'PhotoApp' : 'PhotoApp',
          );
        } catch (_) {
          // The task itself is complete; the transfer UI will still report it.
        }
      }
      break;
    }
  }

  Future<void> cancel(String taskId) async {
    await _downloader.cancelTaskWithId(taskId);
  }

  Future<void> pause(String taskId) async {
    await _downloader.pause(taskId: taskId);
  }

  Future<void> resume(String taskId) async {
    await _downloader.resume(taskId: taskId);
  }

  void dismissFinished() {
    _items.removeWhere((_, item) => item.status.isFinalState);
    notifyListeners();
  }
}
