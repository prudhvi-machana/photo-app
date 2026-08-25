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

  bool get _isVideo {
    final mime = photo.mimeType.toLowerCase();
    if (mime.startsWith('video/')) return true;

    final name = photo.originalFilename.toLowerCase();
    return const ['.mp4', '.mov', '.m4v', '.webm', '.3gp']
        .any(name.endsWith);
  }

  @override
  Widget build(BuildContext context) {
    if (photo.thumbnailUrl == null) {
      return _fallback(context);
    }

    final url = '${ApiConfig.baseUrl}${photo.thumbnailUrl}';

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          headers: {'Authorization': 'Bearer $token'},
          errorBuilder: (context, error, stackTrace) => _fallback(context),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
        ),
        if (_isVideo)
          const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      color: Colors.grey.shade900,
      child: Center(
        child: Icon(
          _isVideo ? Icons.movie_outlined : Icons.broken_image,
          color: Colors.white70,
          size: 48,
        ),
      ),
    );
  }
}
