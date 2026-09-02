import 'package:flutter/material.dart';

import '../models/album.dart';
import '../models/photo.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'album_photos_screen.dart';
import 'create_album_screen.dart';
import 'favorites_screen.dart';
import 'rename_album_screen.dart';
import 'trash_screen.dart';
import 'upload_photos_screen.dart';

class AlbumsScreen extends StatefulWidget {
  final String token;

  const AlbumsScreen({super.key, required this.token});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  final ApiService _apiService = ApiService();
  List<Album> _albums = [];
  List<Photo> _recentPhotos = [];
  List<Photo> _favoritePhotos = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final results = await Future.wait([
        _apiService.getAlbums(),
        _apiService.getRecentPhotos(),
        _apiService.getFavoritePhotos(),
      ]);
      if (!mounted) return;
      setState(() {
        _albums = results[0] as List<Album>;
        _recentPhotos = results[1] as List<Photo>;
        _favoritePhotos = results[2] as List<Photo>;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load photos and albums.';
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadAlbums();
  }

  void _openAlbum(Album album) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlbumPhotosScreen(
        albumId: album.id,
        albumName: album.name,
        token: widget.token,
      ),
    )).then((_) {
      if (mounted) _refresh();
    });
  }

  void _openRecent() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlbumPhotosScreen(
        albumName: 'Recent',
        token: widget.token,
        isRecent: true,
      ),
    )).then((_) {
      if (mounted) _refresh();
    });
  }

  void _openFavorites() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FavoritesScreen(token: widget.token),
    )).then((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _openCreateAlbum() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CreateAlbumScreen(token: widget.token),
    ));
    if (created == true && mounted) await _refresh();
  }

  Future<void> _openUploadPhotos() async {
    final uploaded = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => UploadPhotosScreen(token: widget.token),
    ));
    if (uploaded == true && mounted) await _refresh();
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Upload Photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openUploadPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('Create Album'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openCreateAlbum();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAlbumMenu(Album album) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(dialogContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(dialogContext, 'delete'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _renameAlbum(album);
    if (action == 'delete') await _confirmDeleteAlbum(album);
  }

  Future<void> _renameAlbum(Album album) async {
    final newName = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => RenameAlbumScreen(albumName: album.name),
    ));
    if (newName == null || newName.isEmpty || newName == album.name) return;
    try {
      await _apiService.updateAlbum(album.id, newName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Album renamed successfully.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to rename album: $e')));
    }
  }

  Future<void> _confirmDeleteAlbum(Album album) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Album?'),
        content: Text('Are you sure you want to delete "${album.name}"?\n\nThe photos themselves will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    try {
      await _apiService.deleteAlbum(album.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Album deleted successfully.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete album: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: [
          IconButton(
            tooltip: 'Trash',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TrashScreen(token: widget.token),
              ));
              if (mounted) await _refresh();
            },
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
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
            FilledButton(onPressed: _refresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAlbums,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Albums',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == 0) return _buildFavoritesAlbumCard();
                  if (index == 1) return _buildRecentAlbumCard();
                  return _buildAlbumCard(_albums[index - 2]);
                },
                childCount: _albums.length + 2,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 20,
                childAspectRatio: 0.78,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesAlbumCard() {
    return GestureDetector(
      onTap: _openFavorites,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildFavoritesCover(),
                ),
                if (_favoritePhotos.isNotEmpty)
                  Positioned(right: 10, bottom: 10, child: _buildPhotoCountBadge(_favoritePhotos.length)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Favourites', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            _favoritePhotos.length == 1 ? '1 photo' : '${_favoritePhotos.length} photos',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesCover() {
    if (_favoritePhotos.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.favorite_border, size: 52, color: Theme.of(context).colorScheme.primary),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PhotoThumbnail(photo: _favoritePhotos.first, token: widget.token),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                ),
              ),
            ),
          ),
        ),
        const Center(child: Icon(Icons.favorite, color: Colors.white, size: 44)),
      ],
    );
  }

  Widget _buildRecentAlbumCard() {
    return GestureDetector(
      onTap: _openRecent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(16), child: _buildRecentCover()),
                if (_recentPhotos.isNotEmpty)
                  Positioned(right: 10, bottom: 10, child: _buildPhotoCountBadge(_recentPhotos.length)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Recent', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_recentPhotos.length == 1 ? '1 photo' : '${_recentPhotos.length} photos', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildRecentCover() {
    if (_recentPhotos.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.access_time, size: 52, color: Theme.of(context).colorScheme.primary),
      );
    }
    return PhotoThumbnail(photo: _recentPhotos.first, token: widget.token);
  }

  Widget _buildAlbumCard(Album album) {
    return GestureDetector(
      onTap: () => _openAlbum(album),
      onLongPress: () => _showAlbumMenu(album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(16), child: _buildAlbumCover(album)),
                if (album.photoCount > 0)
                  Positioned(right: 10, bottom: 10, child: _buildPhotoCountBadge(album.photoCount)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(album.photoCount == 1 ? '1 photo' : '${album.photoCount} photos', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildPhotoCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAlbumCover(Album album) {
    if (album.thumbnailUrl == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_album_outlined, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text('Empty album', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      );
    }

    return Image.network(
      '${ApiConfig.baseUrl}${album.thumbnailUrl}',
      headers: {'Authorization': 'Bearer ${widget.token}'},
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
      ),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
