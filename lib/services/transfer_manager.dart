import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'api_config.dart';

class TransferManager {
  static const MethodChannel _channel = MethodChannel('photo_app/background_transfer');

  static Future<void> initialize() async {}

  static Future<String> enqueueMediaBatch({
    required List<MediaTransferItem> items,
    required String token,
    required String refreshToken,
    int? albumId,
  }) async {
    if (items.isEmpty) throw Exception('No media selected');

    final stagingDirectory = Directory('${(await getApplicationSupportDirectory()).path}/pending_uploads');
    await stagingDirectory.create(recursive: true);

    final stagedItems = <Map<String, dynamic>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final source = File(item.path);
      if (!await source.exists()) {
        throw Exception('Selected file is no longer available: ${item.filename}');
      }

      final safeName = '${DateTime.now().microsecondsSinceEpoch}_${index}_${_safeFilename(item.filename)}';
      final destination = File('${stagingDirectory.path}/$safeName');
      await source.copy(destination.path);

      stagedItems.add({
        'path': destination.path,
        'filename': item.filename,
        'type': item.isVideo ? 'video' : 'photo',
      });
    }

    try {
      final batchId = await _channel.invokeMethod<String>('enqueueMediaBatch', {
        'token': token,
        'refreshToken': refreshToken,
        'baseUrl': ApiConfig.baseUrl,
        'albumId': albumId ?? -1,
        'items': stagedItems,
      });
      if (batchId == null || batchId.isEmpty) {
        throw Exception('Could not create background upload batch');
      }
      return batchId;
    } catch (_) {
      for (final item in stagedItems) {
        final file = File(item['path'] as String);
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  static String _safeFilename(String filename) {
    return filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}

class MediaTransferItem {
  final String path;
  final String filename;
  final bool isVideo;

  const MediaTransferItem({
    required this.path,
    required this.filename,
    required this.isVideo,
  });
}
