import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'photo_viewer_screen.dart';

class AlbumPhotosScreen extends StatefulWidget {
  final int? albumId;
  final String albumName;
  final String token;
  final bool isRecent;

  const AlbumPhotosScreen({
    super.key,
    this.albumId,
    required this.albumName,
    required this.token,
    this.isRecent = false,
  }) : assert(isRecent || albumId != null, 'albumId is required for a normal album');

  @override
  State<AlbumPhotosScreen> createState() => _AlbumPhotosScreenState();
}

class _AlbumPhotosScreenState extends State<AlbumPhotosScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  final Map<int, Offset> _pointers = {};
  final Map<int, GlobalKey> _tileKeys = {};

  List<Photo> _photos = [];
  final Set<int> _selectedPhotoIds = {};

  bool _isLoading = true;
  bool _isSelectionMode = false;
  bool _isRemoving = false;
  bool _isAddingToAlbum = false;
  bool _isPinching = false;
  bool _isSwipeSelecting = false;
  String? _errorMessage;

  int _crossAxisCount = 3;
  int _pinchStartColumns = 3;
  double? _pinchStartDistance;
  double _lastPinchRatio = 1;
  static const double _pinchThreshold = .10;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
    _loadPhotos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = widget.isRecent
          ? await _apiService.getRecentPhotos()
          : await _apiService.getAlbumPhotos(widget.albumId!);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = widget.isRecent
            ? 'Failed to load recent photos.'
            : 'Failed to load album photos.';
      });
    }
  }

  GlobalKey _tileKey(int index) =>
      _tileKeys.putIfAbsent(index, GlobalKey.new);

  void _openPhoto(Photo photo, int index) {
    if (_isSelectionMode) {
      _toggleSelection(photo);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PhotoViewerScreen(
            photos: _photos,
            initialIndex: index,
            token: widget.token,
          ),
        ))
        .then((result) {
          if (result == true && mounted) _loadPhotos();
        });
  }

  void _startSelection(Photo photo) {
    setState(() {
      _isSelectionMode = true;
      _isSwipeSelecting = true;
      _selectedPhotoIds.add(photo.id);
    });
  }

  void _toggleSelection(Photo photo) {
    setState(() {
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
      } else {
        _selectedPhotoIds.add(photo.id);
      }
      if (_selectedPhotoIds.isEmpty) _isSelectionMode = false;
    });
  }

  void _selectAll() {
    setState(() {
      final allSelected = _photos.isNotEmpty && _selectedPhotoIds.length == _photos.length;
      _isSelectionMode = true;
      if (allSelected) {
        _selectedPhotoIds.clear();
      } else {
        _selectedPhotoIds
          ..clear()
          ..addAll(_photos.map((photo) => photo.id));
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
      _isSwipeSelecting = false;
    });
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _isSwipeSelecting = false;
      _pinchStartDistance = _distanceBetweenPointers();
      _pinchStartColumns = _crossAxisCount;
      _lastPinchRatio = 1;
      setState(() => _isPinching = true);
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;

    if (_isPinching && _pointers.length == 2 && _pinchStartDistance != null) {
      final distance = _distanceBetweenPointers();
      if (distance <= 0) return;
      final ratio = _pinchStartDistance! / distance;
      if ((ratio - 1).abs() < _pinchThreshold) return;
      if ((ratio - _lastPinchRatio).abs() < .025) return;
      _lastPinchRatio = ratio;
      final next = (_pinchStartColumns * ratio).round().clamp(2, 6);
      if (next == _crossAxisCount) return;

      final oldColumns = _crossAxisCount;
      final anchor = _captureGridAnchor(oldColumns);
      setState(() => _crossAxisCount = next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final target = _offsetForAnchor(anchor, next);
        _scrollController.jumpTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      });
      return;
    }

    if (_isSelectionMode && _isSwipeSelecting && !_isPinching) {
      _selectTileAt(event.position);
    }
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _isPinching) {
      _pinchStartDistance = null;
      setState(() => _isPinching = false);
    }
    if (_pointers.isEmpty) _isSwipeSelecting = false;
  }

  double _distanceBetweenPointers() {
    if (_pointers.length < 2) return 0;
    final values = _pointers.values.toList();
    final dx = values[0].dx - values[1].dx;
    final dy = values[0].dy - values[1].dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  _GridAnchor _captureGridAnchor(int columns) {
    if (!_scrollController.hasClients || _photos.isEmpty) return const _GridAnchor(0, 0);
    final width = MediaQuery.sizeOf(context).width;
    final tile = (width - 8 - 4 * (columns - 1)) / columns;
    final row = (_scrollController.offset / (tile + 4)).floor();
    final index = math.min(_photos.length - 1, math.max(0, row * columns));
    final remainder = _scrollController.offset - row * (tile + 4);
    return _GridAnchor(index, remainder.clamp(0.0, tile + 4));
  }

  double _offsetForAnchor(_GridAnchor anchor, int columns) {
    final width = MediaQuery.sizeOf(context).width;
    final tile = (width - 8 - 4 * (columns - 1)) / columns;
    final row = anchor.index ~/ columns;
    return row * (tile + 4) + anchor.offset;
  }

  void _selectTileAt(Offset globalPosition) {
    for (var i = 0; i < _photos.length; i++) {
      final key = _tileKey(i);
      final object = key.currentContext?.findRenderObject();
      if (object is! RenderBox) continue;
      final topLeft = object.localToGlobal(Offset.zero);
      final rect = topLeft & object.size;
      if (rect.contains(globalPosition)) {
        final photo = _photos[i];
        if (!_selectedPhotoIds.contains(photo.id)) {
          setState(() => _selectedPhotoIds.add(photo.id));
        }
        break;
      }
    }
  }

  // The existing album actions are intentionally kept below this point.
  Future<void> _showAlbumPicker() async {
    if (_selectedPhotoIds.isEmpty || _isAddingToAlbum) return;
    setState(() => _isAddingToAlbum = true);
    try {
      final albums = await _apiService.getAlbums();
      if (!mounted) return;
      setState(() => _isAddingToAlbum = false);
      final available = widget.isRecent
          ? albums
          : albums.where((a) => a.id != widget.albumId).toList();
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other albums available.')));
        return;
      }
      final selected = await _showAlbumSelectionDialog(title: 'Add to album', albums: available);
      if (selected != null && mounted) await _addSelectedPhotosToAlbum(selected);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAddingToAlbum = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load albums: $e')));
    }
  }

  Future<void> _addSelectedPhotosToAlbum(Album destination) async {
    final ids = List<int>.from(_selectedPhotoIds);
    setState(() => _isAddingToAlbum = true);
    var added = 0, already = 0, failed = 0;
    for (final id in ids) {
      try {
        await _apiService.addPhotoToAlbum(destination.id, id);
        added++;
      } catch (e) {
        if (e.toString().contains('409')) already++; else failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _isAddingToAlbum = false;
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0 && already == 0
          ? '$added photo${added == 1 ? '' : 's'} added to "${destination.name}".'
          : '$added added, $already already there, $failed failed.'),
    ));
  }

  Future<void> _showMoveAlbumPicker() async {
    if (widget.isRecent || widget.albumId == null || _selectedPhotoIds.isEmpty || _isAddingToAlbum) return;
    try {
      final albums = await _apiService.getAlbums();
      if (!mounted) return;
      final available = albums.where((a) => a.id != widget.albumId).toList();
      if (available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other albums available.')));
        return;
      }
      final selected = await _showAlbumSelectionDialog(title: 'Move to album', albums: available);
      if (selected != null && mounted) await _moveSelectedPhotosToAlbum(selected);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load albums: $e')));
    }
  }

  Future<void> _moveSelectedPhotosToAlbum(Album destination) async {
    if (widget.albumId == null) return;
    final ids = List<int>.from(_selectedPhotoIds);
    setState(() => _isAddingToAlbum = true);
    var moved = 0, failed = 0;
    for (final id in ids) {
      try {
        await _apiService.movePhotoToAlbum(widget.albumId!, destination.id, id);
        moved++;
      } catch (_) { failed++; }
    }
    if (!mounted) return;
    setState(() {
      _isAddingToAlbum = false;
      if (failed == 0) _photos.removeWhere((p) => ids.contains(p.id));
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed == 0 ? '$moved photo${moved == 1 ? '' : 's'} moved to "${destination.name}".' : '$moved moved, $failed failed.')));
  }

  Future<void> _removeSelectedPhotos() async {
    if (widget.isRecent || widget.albumId == null || _selectedPhotoIds.isEmpty || _isRemoving) return;
    final count = _selectedPhotoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from album?'),
        content: Text(count == 1 ? 'Remove this photo from "${widget.albumName}"?' : 'Remove $count photos from "${widget.albumName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isRemoving = true);
    final ids = List<int>.from(_selectedPhotoIds);
    var removed = 0, failed = 0;
    for (final id in ids) {
      try { await _apiService.removePhotoFromAlbum(widget.albumId!, id); removed++; } catch (_) { failed++; }
    }
    if (!mounted) return;
    setState(() {
      _photos.removeWhere((p) => ids.contains(p.id));
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
      _isRemoving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed == 0 ? '$removed photo${removed == 1 ? '' : 's'} removed from album.' : '$removed removed, $failed failed.')));
  }

  Future<void> _moveSelectedPhotosToTrash() async {
    if (_selectedPhotoIds.isEmpty || _isRemoving) return;
    final count = _selectedPhotoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: Text(count == 1 ? 'This photo will be moved to Trash. You can restore it for 30 days.' : '$count photos will be moved to Trash. You can restore them for 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move to Trash')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isRemoving = true);
    final ids = List<int>.from(_selectedPhotoIds);
    var moved = 0, failed = 0;
    for (final id in ids) {
      try { await _apiService.movePhotoToTrash(id); moved++; } catch (_) { failed++; }
    }
    if (!mounted) return;
    setState(() {
      _photos.removeWhere((p) => ids.contains(p.id));
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
      _isRemoving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed == 0 ? '$moved photo${moved == 1 ? '' : 's'} moved to Trash.' : '$moved moved to Trash, $failed failed.')));
  }

  Future<Album?> _showAlbumSelectionDialog({required String title, required List<Album> albums}) {
    return showDialog<Album>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: albums.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final album = albums[index];
              return ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(album.photoCount == 1 ? '1 photo' : '${album.photoCount} photos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, album),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (!_isSelectionMode) {
      return AppBar(
        title: Text(widget.albumName),
        actions: [
          if (_photos.isNotEmpty)
            IconButton(
              tooltip: 'Select photos',
              onPressed: () => setState(() => _isSelectionMode = true),
              icon: const Icon(Icons.checklist),
            ),
        ],
      );
    }
    final count = _selectedPhotoIds.length;
    final allSelected = _photos.isNotEmpty && count == _photos.length;
    return AppBar(
      leading: IconButton(tooltip: 'Cancel selection', onPressed: _clearSelection, icon: const Icon(Icons.close)),
      title: Text('$count selected'),
      actions: [
        TextButton(onPressed: _selectAll, child: Text(allSelected ? 'Deselect all' : 'Select all')),
        IconButton(tooltip: 'Add to album', onPressed: count == 0 || _isAddingToAlbum ? null : _showAlbumPicker, icon: _isAddingToAlbum ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.library_add_outlined)),
        if (!widget.isRecent) ...[
          IconButton(tooltip: 'Move to album', onPressed: count == 0 || _isAddingToAlbum ? null : _showMoveAlbumPicker, icon: const Icon(Icons.drive_file_move_outlined)),
          IconButton(tooltip: 'Remove from album', onPressed: count == 0 || _isRemoving ? null : _removeSelectedPhotos, icon: const Icon(Icons.remove_circle_outline)),
        ],
        IconButton(tooltip: 'Move to Trash', onPressed: count == 0 || _isRemoving ? null : _moveSelectedPhotosToTrash, icon: const Icon(Icons.delete_outline)),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(_errorMessage!), const SizedBox(height: 16), FilledButton(onPressed: () { setState(() => _isLoading = true); _loadPhotos(); }, child: const Text('Retry'))]));
    }
    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPhotos,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Icon(widget.isRecent ? Icons.access_time : Icons.photo_album_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Center(child: Text(widget.isRecent ? 'No recent photos' : 'This album is empty', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500))),
          ],
        ),
      );
    }

    return Listener(
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: RefreshIndicator(
        onRefresh: _loadPhotos,
        child: GridView.builder(
          controller: _scrollController,
          physics: _isPinching || _isSwipeSelecting ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(4),
          itemCount: _photos.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _crossAxisCount,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final photo = _photos[index];
            final selected = _selectedPhotoIds.contains(photo.id);
            return GestureDetector(
              key: _tileKey(index),
              onTap: () => _openPhoto(photo, index),
              onLongPress: () => _startSelection(photo),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: PhotoThumbnail(photo: photo, token: widget.token)),
                  if (selected)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .35),
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  if (_isSelectionMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 25,
                        height: 25,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? Theme.of(context).colorScheme.primary : Colors.black.withValues(alpha: .45),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: selected ? const Icon(Icons.check, size: 17, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: _buildAppBar(), body: _buildBody());
}

class _GridAnchor {
  final int index;
  final double offset;
  const _GridAnchor(this.index, this.offset);
}
