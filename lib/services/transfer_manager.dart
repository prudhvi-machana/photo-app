import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

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
      group: 'media-transfers',
      taskStatusCallback: _onStatus,
      taskProgressCallback: _onProgress,
    );
    _downloader.configureNotificationForGroup(
      'media-transfers',
      running: const TaskNotification('Photo Storage', '{displayName} • {progress}'),
      complete: const TaskNotification('Photo Storage', '{displayName} completed'),
      error: const TaskNotification('Photo Storage', '{displayName} failed'),
      paused: const TaskNotification('Photo Storage', '{displayName} paused'),
      progressBar: true,
    );
    await _downloader.trackTasksInGroup('media-transfers');
    await _downloader.resumeFromBackground();
  }

  void _onStatus(TaskStatusUpdate update) {
    final task = update.task;
    final type = task is UploadTask ? 'upload' : 'download';
    final filename = task.displayName.isNotEmpty ? task.displayName : task.filename;
    final item = _items.putIfAbsent(
      task.taskId,
      () => TransferItem(taskId: task.taskId, type: type, filename: filename),
    );
    item.status = update.status;
    if (update.status.isFinalState && update.exception != null) {
      item.error = update.exception.toString();
    }
    notifyListeners();

    if (update.status == TaskStatus.complete && task is DownloadTask) {
      handleDownloadCompletion(update);
    }
  }

  void _onProgress(TaskProgressUpdate update) {
    final task = update.task;
    final type = task is UploadTask ? 'upload' : 'download';
    final filename = task.displayName.isNotEmpty ? task.displayName : task.filename;
    final item = _items.putIfAbsent(
      task.taskId,
      () => TransferItem(taskId: task.taskId, type: type, filename: filename),
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
      group: 'media-transfers',
    );
    _items[task.taskId] = TransferItem(taskId: task.taskId, type: 'upload', filename: filename);
    notifyListeners();
    return _downloader.enqueue(task);
  }

  Future<bool> enqueueDownload({required Photo photo, required String token}) async {
    await initialize();
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
    _items[task.taskId] = TransferItem(taskId: task.taskId, type: 'download', filename: photo.originalFilename);
    notifyListeners();
    return _downloader.enqueue(task);
  }

  Future<void> handleDownloadCompletion(TaskStatusUpdate update) async {
    final task = update.task;
    if (task is! DownloadTask || update.status != TaskStatus.complete) return;
    final isVideo = RegExp(r'\.(mp4|mov|m4v|webm|3gp)$', caseSensitive: false).hasMatch(task.filename);
    try {
      await _downloader.moveToSharedStorage(
        task,
        isVideo ? SharedStorage.video : SharedStorage.images,
        directory: 'PhotoApp',
      );
    } catch (error) {
      _items[task.taskId]?.error = error.toString();
      notifyListeners();
    }
  }

  Future<void> cancel(String taskId) => _downloader.cancelTaskWithId(taskId);

  Future<void> pause(String taskId) async {
    final task = await _downloader.taskForId(taskId);
    if (task is DownloadTask) await _downloader.pause(task);
  }

  Future<void> resume(String taskId) async {
    final task = await _downloader.taskForId(taskId);
    if (task is DownloadTask) await _downloader.resume(task);
  }

  void dismissFinished() {
    _items.removeWhere((_, item) => item.status.isFinalState);
    notifyListeners();
  }
}
