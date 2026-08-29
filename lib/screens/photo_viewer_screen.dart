import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/photo.dart';
import '../services/api_config.dart';

class PhotoViewerScreen extends StatefulWidget {
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
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  bool _isVideo(Photo photo) {
    final mime = photo.mimeType.toLowerCase();
    if (mime.startsWith('video/')) return true;
    final name = photo.originalFilename.toLowerCase();
    return const ['.mp4', '.mov', '.m4v', '.webm', '.3gp'].any(name.endsWith);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final photo = widget.photos[index];
          return _isVideo(photo)
              ? _VideoViewer(photo: photo, token: widget.token)
              : _ImageViewer(photo: photo, token: widget.token);
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
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const CircularProgressIndicator(color: Colors.white),
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image, color: Colors.white, size: 60),
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
  VideoPlayerController? _controller;
  bool _initialized = false;
  Object? _error;
  bool _showControls = true;
  bool _isFullscreen = false;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  String _playbackUrl() {
    if (widget.photo.playbackStatus == 'ready' && widget.photo.playbackUrl != null) {
      final path = widget.photo.playbackUrl!;
      return path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';
    }
    return '${ApiConfig.baseUrl}/photos/${widget.photo.id}';
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(_playbackUrl()),
        httpHeaders: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'video/*',
        },
      );
      _controller = controller;
      controller.addListener(_videoListener);
      await controller.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _videoListener() {
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    var target = value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > value.duration) target = value.duration;
    await controller.seekTo(target);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutes:$seconds'
        : '${duration.inMinutes.toString().padLeft(2, '0')}:$seconds';
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    if (mounted) setState(() => _isFullscreen = enabled);
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_videoListener);
    controller?.dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.error_outline, color: Colors.white, size: 60),
            SizedBox(height: 12),
            Text('Unable to play this video.', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    final controller = _controller;
    if (!_initialized || controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final value = controller.value;
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final isEnded = duration > Duration.zero && position >= duration;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showControls = !_showControls),
      onDoubleTap: _togglePlayPause,
      child: Center(
        child: AspectRatio(
          aspectRatio: value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ControlButton(icon: Icons.replay_10, onPressed: () => _seekBy(const Duration(seconds: -10))),
                              const SizedBox(width: 28),
                              _ControlButton(
                                icon: isEnded ? Icons.replay : value.isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 64,
                                iconSize: 38,
                                onPressed: () {
                                  if (isEnded) {
                                    controller.seekTo(Duration.zero);
                                    controller.play();
                                  } else {
                                    _togglePlayPause();
                                  }
                                },
                              ),
                              const SizedBox(width: 28),
                              _ControlButton(icon: Icons.forward_10, onPressed: () => _seekBy(const Duration(seconds: 10))),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 8,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(_formatDuration(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  const Spacer(),
                                  Text(_formatDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                              SizedBox(
                                height: 28,
                                child: VideoProgressIndicator(
                                  controller,
                                  allowScrubbing: true,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.white,
                                    bufferedColor: Colors.white54,
                                    backgroundColor: Colors.white30,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  PopupMenuButton<double>(
                                    initialValue: _playbackSpeed,
                                    color: const Color(0xFF202124),
                                    onSelected: (speed) {
                                      setState(() => _playbackSpeed = speed);
                                      controller.setPlaybackSpeed(speed);
                                    },
                                    itemBuilder: (context) => [
                                      for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                                        PopupMenuItem(value: speed, child: Text('${speed}x', style: const TextStyle(color: Colors.white))),
                                    ],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _setFullscreen(!_isFullscreen),
                                    icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (value.isBuffering)
                          const Center(
                            child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  const _ControlButton({required this.icon, required this.onPressed, this.size = 50, this.iconSize = 30});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: iconSize)),
      ),
    );
  }
}
