import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/local_media.dart';
import '../models/photo.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../services/download_manager.dart';
import '../services/transfer_manager.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<Photo> photos;
  final List<LocalMedia> localMedia;
  final int initialIndex;
  final AssetEntity? initialLocalAsset;
  final String token;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    this.localMedia = const [],
    required this.initialIndex,
    this.initialLocalAsset,
    required this.token,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _ViewerItem {
  final Photo? cloud;
  final LocalMedia? local;

  const _ViewerItem.cloud(this.cloud) : local = null;
  const _ViewerItem.local(this.local) : cloud = null;

  bool get isCloud => cloud != null;
  DateTime get date => isCloud
      ? DateTime.parse(cloud!.uploadedAt).toLocal()
      : local!.createdAt;
  String get identity => isCloud
      ? 'cloud:${cloud!.id}'
      : 'local:${local!.asset.id}';
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late final List<_ViewerItem> _items;
  final ApiService _apiService = ApiService();
  final Set<String> _favoriteIds = {};

  int _currentIndex = 0;
  bool _isInteractingWithImage = false;
  bool _isActionRunning = false;
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
    _items = _buildItems();
    _currentIndex = _initialViewerIndex();
    _pageController = PageController(initialPage: _currentIndex);
    _loadFavorites();
  }

  List<_ViewerItem> _buildItems() {
    final items = <_ViewerItem>[];
    final cloudNames = <String>{};

    for (final photo in widget.photos) {
      items.add(_ViewerItem.cloud(photo));
      final name = photo.originalFilename.trim().toLowerCase();
      if (name.isNotEmpty) cloudNames.add(name);
    }

    // Keep this consistent with PhotosScreen: a local file whose filename is
    // already represented by a cloud photo is not shown as a second item.
    for (final media in widget.localMedia) {
      final name = media.filename.trim().toLowerCase();
      if (name.isEmpty || !cloudNames.contains(name)) {
        items.add(_ViewerItem.local(media));
      }
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  int _initialViewerIndex() {
    if (_items.isEmpty) return 0;

    if (widget.initialLocalAsset != null) {
      final id = 'local:${widget.initialLocalAsset!.id}';
      final index = _items.indexWhere((item) => item.identity == id);
      if (index >= 0) return index;
    }

    if (widget.initialIndex >= 0 && widget.initialIndex < widget.photos.length) {
      final id = 'cloud:${widget.photos[widget.initialIndex].id}';
      final index = _items.indexWhere((item) => item.identity == id);
      if (index >= 0) return index;
    }

    return 0;
  }

  bool _isVideo(_ViewerItem item) {
    if (!item.isCloud) return item.local!.isVideo;
    final photo = item.cloud!;
    final mime = photo.mimeType.toLowerCase();
    if (mime.startsWith('video/')) return true;
    final name = photo.originalFilename.toLowerCase();
    return const ['.mp4', '.mov', '.m4v', '.webm', '.3gp'].any(name.endsWith);
  }

  _ViewerItem get _currentItem => _items[_currentIndex];

  bool get _currentIsFavorite => _favoriteIds.contains(_currentItem.identity);

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('favorite_media_ids') ?? const [];
    if (!mounted) return;
    setState(() => _favoriteIds.addAll(saved));
  }

  Future<void> _toggleFavorite() async {
    final id = _currentItem.identity;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteIds.contains(id)) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
    await prefs.setStringList('favorite_media_ids', _favoriteIds.toList());
  }

  Future<void> _downloadCurrent() async {
    final item = _currentItem;
    if (!item.isCloud || _isActionRunning) return;
    final photo = item.cloud!;
    try {
      await DownloadManager.enqueue(
        photoId: photo.id,
        filename: photo.originalFilename,
        mimeType: photo.mimeType,
        token: widget.token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download started. Check notifications for progress.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start download: $error')),
      );
    }
  }

  Future<void> _deleteCurrent() async {
    final item = _currentItem;
    if (!item.isCloud || _isActionRunning) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: const Text(
          'This photo will be moved to Trash. You can restore it for 30 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionRunning = true);
    try {
      await _apiService.movePhotoToTrash(item.cloud!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo moved to Trash.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isActionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move photo to Trash: $error')),
      );
    }
  }

  Future<void> _uploadCurrent() async {
    final item = _currentItem;
    if (item.isCloud || _isActionRunning) return;

    final media = item.local!;
    final file = await media.asset.file;
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to access this media file.')),
      );
      return;
    }

    setState(() => _isActionRunning = true);
    try {
      await TransferManager.enqueueMediaBatch(
        items: [
          MediaTransferItem(
            path: file.path,
            filename: media.filename.isEmpty ? 'media' : media.filename,
            isVideo: media.isVideo,
          ),
        ],
        token: widget.token,
      );
      if (!mounted) return;
      setState(() => _isActionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload started. Check transfer notifications for progress.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isActionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start upload: $error')),
      );
    }
  }

  void _setImageInteraction(bool active) {
    if (_isInteractingWithImage != active && mounted) {
      setState(() => _isInteractingWithImage = active);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][local.month - 1];
    return '$month ${local.day}, ${local.year} • '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _showDetails() {
    setState(() => _detailsOpen = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailsSheet(
        item: _currentItem,
        isVideo: _isVideo(_currentItem),
        formatBytes: _formatBytes,
        formatDate: _formatDate,
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _detailsOpen = false);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No media available.', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final currentItem = _currentItem;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isActionRunning ? null : _toggleFavorite,
            icon: Icon(_currentIsFavorite ? Icons.favorite : Icons.favorite_border),
            tooltip: _currentIsFavorite ? 'Remove from favourites' : 'Add to favourites',
          ),
          if (currentItem.isCloud)
            IconButton(
              onPressed: _isActionRunning ? null : _downloadCurrent,
              icon: const Icon(Icons.download),
              tooltip: 'Download',
            )
          else
            IconButton(
              onPressed: _isActionRunning ? null : _uploadCurrent,
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Upload to cloud',
            ),
          if (currentItem.isCloud)
            IconButton(
              onPressed: _isActionRunning ? null : _deleteCurrent,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Move to Trash',
            ),
          IconButton(
            onPressed: _detailsOpen ? null : _showDetails,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Details',
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _items.length,
            physics: _isInteractingWithImage
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final item = _items[index];
              if (_isVideo(item)) {
                return _VideoViewer(item: item, token: widget.token);
              }

              return _ImageViewer(
                item: item,
                token: widget.token,
                onInteractionStart: (details) {
                  if (details.pointerCount >= 2) _setImageInteraction(true);
                },
                onInteractionEnd: (_) => _setImageInteraction(false),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! < -4) {
                    _showDetails();
                  }
                },
                child: Container(
                  height: 34,
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white70,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsSheet extends StatelessWidget {
  final _ViewerItem item;
  final bool isVideo;
  final String Function(int) formatBytes;
  final String Function(DateTime) formatDate;

  const _DetailsSheet({
    required this.item,
    required this.isVideo,
    required this.formatBytes,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final filename = item.isCloud
        ? item.cloud!.originalFilename
        : item.local!.filename;
    final mime = item.isCloud
        ? item.cloud!.mimeType
        : (isVideo ? 'Video' : 'Image');
    final date = item.date;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _DetailRow(label: 'Name', value: filename.isEmpty ? 'Unknown' : filename),
              _DetailRow(label: 'Type', value: mime),
              _DetailRow(
                label: item.isCloud ? 'Uploaded' : 'Date taken',
                value: formatDate(date),
              ),
              if (item.isCloud)
                _DetailRow(label: 'Size', value: formatBytes(item.cloud!.size)),
              if (!item.isCloud)
                _DetailRow(
                  label: 'Resolution',
                  value: '${item.local!.asset.width} × ${item.local!.asset.height}',
                ),
              if (item.isCloud)
                _DetailRow(label: 'Cloud ID', value: '${item.cloud!.id}'),
              if (!item.isCloud)
                _DetailRow(label: 'Local ID', value: item.local!.asset.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, maxLines: 4, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final _ViewerItem item;
  final String token;
  final ValueChanged<ScaleStartDetails> onInteractionStart;
  final ValueChanged<ScaleEndDetails> onInteractionEnd;

  const _ImageViewer({
    required this.item,
    required this.token,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  @override
  Widget build(BuildContext context) {
    final Widget image = item.isCloud
        ? Image.network(
            '${ApiConfig.baseUrl}/photos/${item.cloud!.id}',
            headers: {'Authorization': 'Bearer $token'},
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const CircularProgressIndicator(color: Colors.white),
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 60),
          )
        : AssetEntityImage(
            item.local!.asset,
            isOriginal: true,
            fit: BoxFit.contain,
            thumbnailSize: ThumbnailSize(
              item.local!.asset.width,
              item.local!.asset.height,
            ),
            thumbnailFormat: ThumbnailFormat.jpeg,
          );

    return Center(
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(24),
        panEnabled: true,
        scaleEnabled: true,
        onInteractionStart: onInteractionStart,
        onInteractionEnd: onInteractionEnd,
        child: image,
      ),
    );
  }
}

class _VideoViewer extends StatefulWidget {
  final _ViewerItem item;
  final String token;

  const _VideoViewer({required this.item, required this.token});

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

  bool get _isCloud => widget.item.isCloud;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      late final VideoPlayerController controller;

      if (_isCloud) {
        final photo = widget.item.cloud!;
        String playbackUrl() {
          if (photo.playbackStatus == 'ready' && photo.playbackUrl != null) {
            final path = photo.playbackUrl!;
            return path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';
          }
          return '${ApiConfig.baseUrl}/photos/${photo.id}';
        }

        controller = VideoPlayerController.networkUrl(
          Uri.parse(playbackUrl()),
          httpHeaders: {
            'Authorization': 'Bearer ${widget.token}',
            'Accept': 'video/*',
          },
        );
      } else {
        final file = await widget.item.local!.asset.file;
        if (file == null) throw Exception('Unable to access video file.');
        controller = VideoPlayerController.file(file);
      }

      _controller = controller;
      controller.addListener(_videoListener);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                              _ControlButton(
                                icon: Icons.replay_10,
                                onPressed: () => _seekBy(const Duration(seconds: -10)),
                              ),
                              const SizedBox(width: 28),
                              _ControlButton(
                                icon: isEnded
                                    ? Icons.replay
                                    : value.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
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
                              _ControlButton(
                                icon: Icons.forward_10,
                                onPressed: () => _seekBy(const Duration(seconds: 10)),
                              ),
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
                                  Text(
                                    _formatDuration(position),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(duration),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
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
                                        PopupMenuItem(
                                          value: speed,
                                          child: Text(
                                            '${speed}x',
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                        ),
                                    ],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(
                                        '${_playbackSpeed}x',
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _setFullscreen(!_isFullscreen),
                                    icon: Icon(
                                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (value.isBuffering)
                          const Center(
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
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

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 50,
    this.iconSize = 30,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.42),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      );
}
