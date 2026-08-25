import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/photo.dart';
import '../services/api_config.dart';
import '../services/transfer_manager.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;
  final String token;

  const PhotoViewerScreen({super.key, required this.photos, required this.initialIndex, required this.token});

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    TransferManager.instance.initialize();
  }

  Photo get _currentPhoto => widget.photos[_currentIndex];

  bool _isVideo(Photo photo) {
    final mime = photo.mimeType.toLowerCase();
    if (mime.startsWith('video/')) return true;
    final name = photo.originalFilename.toLowerCase();
    return const ['.mp4', '.mov', '.m4v', '.webm', '.3gp'].any(name.endsWith);
  }

  Future<void> _downloadCurrent() async {
    try {
      await TransferManager.instance.enqueueDownload(photo: _currentPhoto, token: widget.token);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed to start: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [IconButton(onPressed: _downloadCurrent, icon: const Icon(Icons.download), tooltip: 'Download')],
      ),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final photo = widget.photos[index];
          return _isVideo(photo) ? _VideoViewer(photo: photo, token: widget.token) : _ImageViewer(photo: photo, token: widget.token);
        },
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final Photo photo;
  final String token;
  const _ImageViewer({required this.photo, required this.token});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 4.0,
        child: Image.network(
          '${ApiConfig.baseUrl}/photos/${photo.id}',
          headers: {'Authorization': 'Bearer $token'},
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null ? child : const CircularProgressIndicator(color: Colors.white),
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white, size: 60),
        ),
      ),
    );
  }
}

class _VideoViewer extends StatefulWidget {
  final Photo photo;
  final String token;
  const _VideoViewer({required this.photo, required this.token});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse('${ApiConfig.baseUrl}/photos/${widget.photo.id}'),
      formatHint: VideoFormat.other,
      httpHeaders: {'Authorization': 'Bearer ${widget.token}'},
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller.addListener(_onPlayerChanged);
    _initialize();
  }

  void _onPlayerChanged() {
    if (!mounted || !_controller.value.hasError) return;
    if (_error == null) setState(() => _error = _controller.value.errorDescription ?? 'Unknown player error');
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 60),
              const SizedBox(height: 12),
              const Text('Unable to play this video.', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text('$_error', style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (!_initialized) return const Center(child: CircularProgressIndicator(color: Colors.white));

    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            GestureDetector(
              onTap: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
              child: AnimatedOpacity(
                opacity: _controller.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 72),
              ),
            ),
            Positioned(left: 12, right: 12, bottom: 8, child: VideoProgressIndicator(_controller, allowScrubbing: true)),
          ],
        ),
      ),
    );
  }
}
