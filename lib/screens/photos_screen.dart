import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../models/local_media.dart';
import '../models/photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'local_media_viewer_screen.dart';
import 'photo_viewer_screen.dart';
import 'trash_screen.dart';
import 'upload_photos_screen.dart';

class PhotosScreen extends StatefulWidget {
  final String token;

  const PhotosScreen({super.key, required this.token});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final ApiService _apiService = ApiService();

  List<Photo> _cloudPhotos = [];
  List<LocalMedia> _localMedia = [];
  bool _isLoading = true;
  bool _hasLocalPermission = false;
  String? _errorMessage;

  int _crossAxisCount = 3;
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  int _pinchStartColumns = 3;
  bool _isPinching = false;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    try {
      final cloudFuture = _apiService.getPhotos();
      final permission = await PhotoManager.requestPermissionExtend();
      List<LocalMedia> local = [];

      if (permission.hasAccess) {
        final assets = await PhotoManager.getAssetListRange(
          start: 0,
          end: 500,
          type: RequestType.common,
        );
        local = [
          for (final asset in assets)
            if (!asset.isTrashed)
              LocalMedia(
                asset: asset,
                filename: await asset.titleAsync,
              ),
        ];
      }

      final cloud = await cloudFuture;
      final localNames = <String>{
        for (final item in local) item.filename.trim().toLowerCase(),
      };

      // Existing server records currently expose the original filename but
      // not a device-side content hash. Filename matching is therefore a
      // conservative first-pass indicator for "both"; exact hash matching
      // can be added later without changing the UI model.
      local = [
        for (final item in local)
          LocalMedia(
            asset: item.asset,
            filename: item.filename,
            alsoInCloud: cloud.any(
              (photo) =>
                  photo.originalFilename.trim().toLowerCase() ==
                  item.filename.trim().toLowerCase(),
            ),
          ),
      ];

      if (!mounted) return;
      setState(() {
        _cloudPhotos = cloud;
        _localMedia = local;
        _hasLocalPermission = permission.hasAccess;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load photos.';
      });
    }
  }

  Future<void> _refresh() async => _loadMedia();

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _pinchStartDistance = _distanceBetweenPointers();
      _pinchStartColumns = _crossAxisCount;
      setState(() => _isPinching = true);
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (!_isPinching || _pointers.length < 2 || _pinchStartDistance == null) return;

    final currentDistance = _distanceBetweenPointers();
    if (currentDistance <= 0) return;

    // Finger separation is used directly instead of Flutter's generic scale
    // recognizer. This keeps the grid scroll and RefreshIndicator out of the
    // pinch gesture arena.
    final ratio = _pinchStartDistance! / currentDistance;
    final next = (_pinchStartColumns * ratio).round().clamp(2, 6);
    if (next != _crossAxisCount) {
      setState(() => _crossAxisCount = next);
    }
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _isPinching) {
      _pinchStartDistance = null;
      setState(() => _isPinching = false);
    }
  }

  double _distanceBetweenPointers() {
    if (_pointers.length < 2) return 0;
    final values = _pointers.values.toList();
    final dx = values[0].dx - values[1].dx;
    final dy = values[0].dy - values[1].dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  Map<DateTime, List<_MediaItem>> _groupMediaByDate() {
    final items = <_MediaItem>[];

    final localNames = <String>{
      for (final item in _localMedia) item.filename.trim().toLowerCase(),
    };

    for (final photo in _cloudPhotos) {
      final localExists = localNames.contains(
        photo.originalFilename.trim().toLowerCase(),
      );
      items.add(_MediaItem.cloud(photo, alsoLocal: localExists));
    }

    // Don't render a second tile for a local asset whose filename matches a
    // cloud record. The local tile represents the same media and carries a
    // combined local+cloud badge.
    final cloudNames = {
      for (final photo in _cloudPhotos)
        photo.originalFilename.trim().toLowerCase(),
    };
    for (final local in _localMedia) {
      if (!cloudNames.contains(local.filename.trim().toLowerCase())) {
        items.add(_MediaItem.local(local));
      } else {
        items.add(_MediaItem.local(local.copyWith(alsoInCloud: true)));
        items.removeWhere((item) =>
            item.isCloud &&
            item.cloud!.originalFilename.trim().toLowerCase() ==
                local.filename.trim().toLowerCase());
      }
    }

    items.sort((a, b) => b.date.compareTo(a.date));

    final groups = <DateTime, List<_MediaItem>>{};
    for (final item in items) {
      final d = item.date;
      final key = DateTime(d.year, d.month, d.day);
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    if (date.year == today.year) return '${months[date.month - 1]} ${date.day}';
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _openCloudPhoto(Photo photo) {
    final index = _cloudPhotos.indexOf(photo);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoViewerScreen(
        photos: _cloudPhotos,
        initialIndex: index,
        token: widget.token,
      ),
    ));
  }

  void _openLocalPhoto(LocalMedia media) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LocalMediaViewerScreen(asset: media.asset),
    ));
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrashScreen(token: widget.token),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _openUploadPhotos() async {
    final uploaded = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => UploadPhotosScreen(token: widget.token),
    ));
    if (uploaded == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Trash',
            icon: const Icon(Icons.delete_outline),
            onPressed: _openTrash,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add photos',
        onPressed: _openUploadPhotos,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadMedia, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (!_hasLocalPermission && _cloudPhotos.isEmpty) {
      return const Center(child: Text('Allow photo access to see your device media.'));
    }

    final groups = _groupMediaByDate();
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final scrollPhysics = _isPinching
        ? const NeverScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: scrollPhysics,
          slivers: [
            if (!_hasLocalPermission)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(
                    'Device photos are hidden until photo access is allowed.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            for (final date in dates) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: Text(
                    _dateLabel(date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = groups[date]![index];
                      return _buildMediaTile(item);
                    },
                    childCount: groups[date]!.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _crossAxisCount,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 1,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaTile(_MediaItem item) {
    if (item.isCloud) {
      return GestureDetector(
        onTap: () => _openCloudPhoto(item.cloud!),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoThumbnail(photo: item.cloud!, token: widget.token),
            _buildStatusBadge(local: item.alsoLocal, cloud: true),
          ],
        ),
      );
    }

    final local = item.local!;
    return GestureDetector(
      onTap: () => _openLocalPhoto(local),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AssetEntityImage(
            local.asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(300),
            thumbnailFormat: ThumbnailFormat.jpeg,
            fit: BoxFit.cover,
          ),
          _buildStatusBadge(local: true, cloud: local.alsoInCloud),
          if (local.isVideo)
            const Positioned(
              right: 8,
              bottom: 8,
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({required bool local, required bool cloud}) {
    final icon = local && cloud
        ? Icons.cloud_done
        : cloud
            ? Icons.cloud_done
            : Icons.smartphone;
    final label = local && cloud
        ? 'On device + cloud'
        : cloud
            ? 'Cloud'
            : 'On device';

    return Positioned(
      top: 5,
      right: 5,
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

class _MediaItem {
  final Photo? cloud;
  final LocalMedia? local;
  final bool alsoLocal;

  const _MediaItem._({this.cloud, this.local, this.alsoLocal});

  factory _MediaItem.cloud(Photo photo, {required bool alsoLocal}) =>
      _MediaItem._(cloud: photo, alsoLocal: alsoLocal);

  factory _MediaItem.local(LocalMedia media) =>
      _MediaItem._(local: media);

  bool get isCloud => cloud != null;
  DateTime get date => isCloud
      ? DateTime.parse(cloud!.uploadedAt).toLocal()
      : local!.createdAt;
}

extension on LocalMedia {
  LocalMedia copyWith({bool? alsoInCloud}) => LocalMedia(
        asset: asset,
        filename: filename,
        alsoInCloud: alsoInCloud ?? this.alsoInCloud,
      );
}
