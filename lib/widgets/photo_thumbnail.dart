import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../services/api_config.dart';

class PhotoThumbnail extends StatelessWidget {
  final Photo photo;
  final String token;

  const PhotoThumbnail({
    super.key,
    required this.photo,
    required this.token,
  });

  bool get _isVideo => photo.mimeType.toLowerCase().startsWith('video/');

  @override
  Widget build(BuildContext context) {
    if (_isVideo || photo.thumbnailUrl == null) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Colors.white,
            size: 48,
          ),
        ),
      );
    }

    final url = '${ApiConfig.baseUrl}${photo.thumbnailUrl}';

    return Image.network(
      url,
      fit: BoxFit.cover,
      headers: {'Authorization': 'Bearer $token'},
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
    );
  }
}
