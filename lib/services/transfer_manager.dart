import 'package:flutter/services.dart';

import 'api_config.dart';

class TransferManager {
  static const MethodChannel _channel = MethodChannel('photo_app/background_transfer');

  static Future<void> initialize() async {
    // Background uploads are now owned by Android WorkManager so video
    // preparation and network transfer can continue after the Flutter UI closes.
  }

  static Future<String> enqueueMediaBatch({
    required List<MediaTransferItem> items,
    required String token,
    int? albumId,
  }) async {
    if (items.isEmpty) {
      throw Exception('No media selected');
    }

    final batchId = await _channel.invokeMethod<String>('enqueueMediaBatch', {
      'token': token,
      'baseUrl': ApiConfig.baseUrl,
      'albumId': albumId ?? -1,
      'items': items
          .map(
            (item) => {
              'path': item.path,
              'filename': item.filename,
              'type': item.isVideo ? 'video' : 'photo',
            },
          )
          .toList(),
    });

    if (batchId == null || batchId.isEmpty) {
      throw Exception('Could not create background upload batch');
    }
    return batchId;
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
