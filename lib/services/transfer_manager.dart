import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

import '../models/photo.dart';
import 'api_config.dart';
import 'api_service.dart';

class TransferItem {
  final String taskId;
  final String type;
  final String filename;
  final int? albumId;
  final String? token;
  final int? totalBytes;
  double progress;
  TaskStatus status;
  String? error;

  TransferItem({
    required this.taskId,
    required this.type,
    required this.filename,
    this.albumId,
    this.token,
    this.totalBytes,
    this.progress = 0,
    this.status = TaskStatus.enqueued,
    this.error,
  });

  int? get transferredBytes => totalBytes == null ? null : (totalBytes! * progress).round();
}

class TransferManager extends ChangeNotifier {
  TransferManager._();
  static final TransferManager instance = TransferManager._();

  final FileDownloader _downloader = FileDownloader();
  final Map<String, TransferItem> _items = {};
  bool _initialized = false;

  List<TransferItem> get items => List.unmodifiable(_items.values);
  List<TransferItem> get activeItems => _items.values.where((item) => !item.status.isFinalState).toList(growable: false);
  int get activeCount => activeItems.length;

  Future<void> initialize() async {
    if (_initialized) return;
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
    _initialized = true;
  }

  TransferItem _getOrCreate(Task task, String type, String filename, {int? totalBytes}) {
    final existing = _items[task.taskId];
    if (existing != null) return existing;
    final item = TransferItem(
      taskId: task.taskId,
      type: type,
      filename: filename,
      totalBytes: totalBytes,
    );
    _items[task.taskId] = item;
    return item;
  }

  void _onStatus(TaskStatusUpdate update) {
    final task = update.task;
    final item = _items[task.taskId] ?? _getOrCreate(
      task,
      task is UploadTask ? 'upload' : 'download',
      task.displayName.isNotEmpty ? task.displayName : task.filename,
    );
    item.status = update.status;
    if (update.exception != null) item.error = update.exception.toString();
    notifyListeners();

    if (update.status == TaskStatus.complete && task is DownloadTask) {
      handleDownloadCompletion(update);
    }
  }

  void _onProgress(TaskProgressUpdate update) {
    final task = update.task;
    final item = _items[task.taskId] ?? _getOrCreate(
      task,
      task is UploadTask ? 'upload' : 'download',
      task.displayName.isNotEmpty ? task.displayName : task.filename,
      totalBytes: update.expectedFileSize > 0 ? update.expectedFileSize : null,
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

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Selected file no longer exists: $path');
    }

    final fileSize = await file.length();
    final fields = <String, String>{};
    if (albumId != null) fields['album_id'] = albumId.toString();

    final task = UploadTask.fromFile(
      file: file,
      url: '${ApiConfig.baseUrl}/photos/upload',
      headers: {'Authorization': 'Bearer $token'},
      fields: fields,
      mimeType: mimeType ?? _mimeTypeFor(filename),
      displayName: filename,
      updates: Updates.statusAndProgress,
      retries: 3,
      priority: 5,
      group: 'media-transfers',
    );

    _items[task.taskId] = TransferItem(
      taskId: task.taskId,
      type: 'upload',
      filename: filename,
      albumId: albumId,
      token: token,
      totalBytes: fileSize,
      status: TaskStatus.enqueued,
    );
    notifyListeners();

    final queued = await _downloader.enqueue(task);
    if (!queued) {
      _items[task.taskId]?.status = TaskStatus.failed;
      _items[task.taskId]?.error = 'Background downloader rejected the upload task.';
      notifyListeners();
      throw Exception('Could not enqueue upload task.');
    }
    return true;
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
      priority: 5,
      allowPause: true,
      group: 'media-transfers',
    );

    _items[task.taskId] = TransferItem(
      taskId: task.taskId,
      type: 'download',
      filename: photo.originalFilename,
      totalBytes: photo.size,
    );
    notifyListeners();

    final queued = await _downloader.enqueue(task);
    if (!queued) {
      _items[task.taskId]?.status = TaskStatus.failed;
      _items[task.taskId]?.error = 'Background downloader rejected the download task.';
      notifyListeners();
      throw Exception('Could not enqueue download task.');
    }
    return true;
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

  String _mimeTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
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
