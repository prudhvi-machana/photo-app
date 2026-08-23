import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../services/api_config.dart';

class PhotoViewerScreen extends StatelessWidget {
  final List<Photo> photos;
  final int initialIndex;
  final String token;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: PageController(
          initialPage: initialIndex,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];

          return Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled: true,
              scaleEnabled: true,
              child: Image.network(
                '${ApiConfig.baseUrl}/photos/${photo.id}',
                headers: {
                  'Authorization': 'Bearer $token',
                },
                fit: BoxFit.contain,
                loadingBuilder:
                    (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }

                  return const CircularProgressIndicator(
                    color: Colors.white,
                  );
                },
                errorBuilder:
                    (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 60,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load image\n$error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}