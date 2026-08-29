import 'package:flutter/services.dart';

import 'api_config.dart';
import 'token_storage.dart';

class DownloadManager {
  static const MethodChannel _channel = MethodChannel('photo_app/background_download');
  static final TokenStorage _tokenStorage = TokenStorage();

  static Future<String> enqueue({
    required int photoId,
    required String filename,
    required String mimeType,
    required String token,
  }) async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('Session cannot be refreshed. Please log in again.');
    }

    final batchId = await _channel.invokeMethod<String>('enqueueDownload', {
      'token': token,
      'refreshToken': refreshToken,
      'baseUrl': ApiConfig.baseUrl,
      'photoId': photoId,
      'filename': filename,
      'mimeType': mimeType,
    });

    if (batchId == null || batchId.isEmpty) {
      throw Exception('Could not start download');
    }
    return batchId;
  }
}
