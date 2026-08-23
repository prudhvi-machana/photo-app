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

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = photo.thumbnailUrl;

    if (thumbnailUrl == null) {
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.image),
      );
    }

    final url = '${ApiConfig.baseUrl}$thumbnailUrl';

    return Image.network(
      url,
      fit: BoxFit.cover,
      headers: {
        'Authorization': 'Bearer $token',
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        );
      },
    );
  }
}