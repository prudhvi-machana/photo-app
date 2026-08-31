import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class LocalMediaViewerScreen extends StatelessWidget {
  final AssetEntity asset;

  const LocalMediaViewerScreen({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          panEnabled: true,
          child: AssetEntityImage(
            asset,
            isOriginal: true,
            fit: BoxFit.contain,
            thumbnailSize: ThumbnailSize(asset.width, asset.height),
            thumbnailFormat: ThumbnailFormat.jpeg,
          ),
        ),
      ),
    );
  }
}
