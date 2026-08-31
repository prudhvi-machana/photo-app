import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

class LocalMediaViewerScreen extends StatefulWidget {
  final AssetEntity asset;

  const LocalMediaViewerScreen({super.key, required this.asset});

  @override
  State<LocalMediaViewerScreen> createState() => _LocalMediaViewerScreenState();
}

class _LocalMediaViewerScreenState extends State<LocalMediaViewerScreen> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _isInitializingVideo = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _isVideo = widget.asset.type == AssetType.video;
    if (_isVideo) _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    setState(() => _isInitializingVideo = true);
    try {
      final file = await widget.asset.file;
      if (file == null) throw Exception('Unable to access video file.');
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _isInitializingVideo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializingVideo = false;
        _videoError = 'Unable to play this video.';
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isVideo ? _buildVideo() : _buildPhoto(),
      ),
    );
  }

  Widget _buildPhoto() {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      panEnabled: true,
      child: AssetEntityImage(
        widget.asset,
        isOriginal: true,
        fit: BoxFit.contain,
        thumbnailSize: ThumbnailSize(widget.asset.width, widget.asset.height),
        thumbnailFormat: ThumbnailFormat.jpeg,
      ),
    );
  }

  Widget _buildVideo() {
    if (_isInitializingVideo) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    if (_videoError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(_videoError!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _initializeVideo,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          AnimatedOpacity(
            opacity: controller.value.isPlaying ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 42),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
