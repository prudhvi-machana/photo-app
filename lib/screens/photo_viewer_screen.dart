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
  final Set<int> _favoriteCloudIds = {};
  final Set<String> _favoriteLocalIds = {};

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

  bool get _currentIsFavorite {
    final item = _currentItem;
    if (item.isCloud) return _favoriteCloudIds.contains(item.cloud!.id);
    return _favoriteLocalIds.contains(item.local!.asset.id);
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('favorite_media_ids') ?? const [];

    if (!mounted) return;
    setState(() {
      _favoriteLocalIds.addAll(
        saved.where((id) => id.startsWith('local:')).map((id) => id.substring(6)),
      );
      _favoriteCloudIds.addAll(
        widget.photos.where((photo) => photo.isFavorite).map((photo) => photo.id),
      );
    });
  }

  Future<void> _toggleFavorite() async {
    final item = _currentItem;

    if (item.isCloud) {
      if (_isActionRunning) return;
      final photo = item.cloud!;
      final currentlyFavorite = _favoriteCloudIds.contains(photo.id);
      setState(() => _isActionRunning = true);
      try {
        await _apiService.setFavorite(photo.id, !currentlyFavorite);
        if (!mounted) return;
        setState(() {
          if (currentlyFavorite) {
            _favoriteCloudIds.remove(photo.id);
          } else {
            _favoriteCloudIds.add(photo.id);
          }
          _isActionRunning = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _isActionRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update favourite: $error')),
        );
      }
      return;
    }

    final id = item.local!.asset.id;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteLocalIds.contains(id)) {
        _favoriteLocalIds.remove(id);
      } else {
        _favoriteLocalIds.add(id);
      }
    });
    await prefs.setStringList(
      'favorite_media_ids',
      _favoriteLocalIds.map((value) => 'local:$value').toList(),
    );
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
        content: const Text('This photo will be moved to Trash. You can restore it for 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Move to Trash')),
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[local.month - 1]} ${local.day}, ${local.year} • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showDetails() async {
    final item = _currentItem;
    int? sizeBytes;
    if (!item.isCloud) {
      final file = await item.local!.asset.file;
      sizeBytes = file?.lengthSync();
    }
    if (!mounted) return;

    setState(() => _detailsOpen = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailsSheet(
        item: item,
        isVideo: _isVideo(item),
        sizeBytes: sizeBytes,
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
        body: Center(child: Text('No media available.', style: TextStyle(color: Colors.white))),
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
            IconButton(onPressed: _isActionRunning ? null : _downloadCurrent, icon: const Icon(Icons.download), tooltip: 'Download')
          else
            IconButton(onPressed: _isActionRunning ? null : _uploadCurrent, icon: const Icon(Icons.cloud_upload_outlined), tooltip: 'Upload to cloud'),
          if (currentItem.isCloud)
            IconButton(onPressed: _isActionRunning ? null : _deleteCurrent, icon: const Icon(Icons.delete_outline), tooltip: 'Move to Trash'),
          IconButton(onPressed: _detailsOpen ? null : _showDetails, icon: const Icon(Icons.info_outline), tooltip: 'Details'),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _items.length,
            physics: _isInteractingWithImage ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final item = _items[index];
              if (_isVideo(item)) {
                return _VideoViewer(
                  item: item,
                  token: widget.token,
                  isActive: index == _currentIndex,
                );
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
                  if (details.primaryDelta != null && details.primaryDelta! < -4) _showDetails();
                },
                child: Container(
                  height: 34,
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(4)),
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
  final int? sizeBytes;
  final String Function(int) formatBytes;
  final String Function(DateTime) formatDate;

  const _DetailsSheet({
    required this.item,
    required this.isVideo,
    required this.sizeBytes,
    required this.formatBytes,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final filename = item.isCloud ? item.cloud!.originalFilename : item.local!.filename;
    final mime = item.isCloud ? item.cloud!.mimeType : (isVideo ? 'Video' : 'Image');
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
              Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 18),
              Text('Details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _DetailRow(label: 'Name', value: filename.isEmpty ? 'Unknown' : filename),
              _DetailRow(label: 'Type', value: mime),
              _DetailRow(label: item.isCloud ? 'Uploaded' : 'Date taken', value: formatDate(date)),
              if (sizeBytes != null) _DetailRow(label: 'Size', value: formatBytes(sizeBytes!)),
              if (!item.isCloud) _DetailRow(label: 'Resolution', value: '${item.local!.asset.width} × ${item.local!.asset.height}'),
              if (item.isCloud) _DetailRow(label: 'Cloud ID', value: '${item.cloud!.id}'),
              if (!item.isCloud) _DetailRow(label: 'Local ID', value: item.local!.asset.id),
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
          SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final _ViewerItem item;
  final String token;
  final GestureScaleStartCallback? onInteractionStart;
  final GestureScaleEndCallback? onInteractionEnd;

  const _ImageViewer({required this.item, required this.token, required this.onInteractionStart, required this.onInteractionEnd});

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (!item.isCloud) {
      image = AssetEntityImage(
        item.local!.asset,
        isOriginal: true,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      final photo = item.cloud!;
      image = Image.network(
        '${ApiConfig.baseUrl}/photos/${photo.id}',
        headers: {'Authorization': 'Bearer $token'},
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56)),
        loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onScaleStart: onInteractionStart,
      onScaleEnd: onInteractionEnd,
      child: SizedBox.expand(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(child: image),
        ),
      ),
    );
  }
}

class _VideoViewer extends StatefulWidget {
  final _ViewerItem item;
  final String token;
  final bool isActive;

  const _VideoViewer({required this.item, required this.token, required this.isActive});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  double _speed = 1.0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _initializeController();
  }

  @override
  void didUpdateWidget(covariant _VideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;

    if (widget.isActive) {
      _initializeController();
    } else {
      _disposeController();
      if (mounted) setState(() {});
    }
  }

  void _disposeController() {
    _generation++;
    final controller = _controller;
    _controller = null;
    _initializeFuture = null;
    controller?.dispose();
  }

  String _cloudPlaybackUrl() {
    final photo = widget.item.cloud!;
    final playbackUrl = photo.playbackUrl;
    if (playbackUrl != null && playbackUrl.isNotEmpty && photo.playbackStatus == 'ready') {
      return playbackUrl.startsWith('http') ? playbackUrl : '${ApiConfig.baseUrl}$playbackUrl';
    }
    return '${ApiConfig.baseUrl}/photos/${photo.id}';
  }

  @override
  void _initializeController() {
    _disposeController();
    final generation = _generation;

    if (widget.item.isCloud) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(_cloudPlaybackUrl()),
        httpHeaders: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'video/*',
        },
      );
      _controller = controller;
      _initializeFuture = controller.initialize().then((_) {
        if (generation != _generation) return;
        if (mounted) setState(() {});
      });
    } else {
      _initializeFuture = widget.item.local!.asset.file.then((file) async {
        if (file == null) throw Exception('Unable to access video file');
        if (generation != _generation) return;
        final controller = VideoPlayerController.file(file);
        _controller = controller;
        await controller.initialize();
        if (generation != _generation) {
          await controller.dispose();
          return;
        }
        if (mounted) setState(() {});
      });
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _seekRelative(int seconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final position = await controller.position;
    final duration = controller.value.duration;
    if (position == null) return;
    final target = position + Duration(seconds: seconds);
    final clamped = target < Duration.zero ? Duration.zero : target > duration ? duration : target;
    await controller.seekTo(clamped);
  }

  Future<void> _selectSpeed() async {
    final controller = _controller;
    if (controller == null) return;
    final speed = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final value in [0.5, 1.0, 1.5, 2.0]) ListTile(title: Text('${value}x'), trailing: _speed == value ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, value))],
        ),
      ),
    );
    if (speed == null || !mounted) return;
    setState(() => _speed = speed);
    await controller.setPlaybackSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return const Center(child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 56));
    }

    final future = _initializeFuture;
    final controller = _controller;
    if (future == null || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Unable to play video.', style: TextStyle(color: Colors.white)));
        if (snapshot.connectionState != ConnectionState.done || !controller.value.isInitialized) return const Center(child: CircularProgressIndicator());

        return Column(
          children: [
            Expanded(child: Center(child: AspectRatio(aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio, child: VideoPlayer(controller)))),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) => Column(
                children: [
                  VideoProgressIndicator(controller, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(onPressed: () => _seekRelative(-10), icon: const Icon(Icons.replay_10, color: Colors.white)),
                        IconButton(
                          onPressed: () async {
                            if (value.isPlaying) {
                              await controller.pause();
                            } else {
                              await controller.play();
                            }
                            if (mounted) setState(() {});
                          },
                          icon: Icon(value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white, size: 38),
                        ),
                        IconButton(onPressed: () => _seekRelative(10), icon: const Icon(Icons.forward_10, color: Colors.white)),
                        const SizedBox(width: 10),
                        TextButton(onPressed: _selectSpeed, child: Text('${_speed}x', style: const TextStyle(color: Colors.white))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
