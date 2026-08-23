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
  }) : assert(
          isRecent || albumId != null,
          'albumId is required for a normal album',
        );

  @override
  State<AlbumPhotosScreen> createState() =>
      _AlbumPhotosScreenState();
}

class _AlbumPhotosScreenState
    extends State<AlbumPhotosScreen> {
  final ApiService _apiService =
      ApiService();

  List<Photo> _photos = [];

  final Set<int> _selectedPhotoIds = {};

  bool _isLoading = true;
  bool _isSelectionMode = false;
  bool _isRemoving = false;
  bool _isAddingToAlbum = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _apiService.setToken(
      widget.token,
    );

    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos =
          widget.isRecent
              ? await _apiService
                  .getRecentPhotos()
              : await _apiService
                  .getAlbumPhotos(
                  widget.albumId!,
                );

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

  // ---------------------------------------------------------------------------
  // PHOTO VIEWER
  // ---------------------------------------------------------------------------

  void _openPhoto(
    Photo photo,
    int index,
  ) {
    if (_isSelectionMode) {
      _toggleSelection(photo);
      return;
    }

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) =>
            PhotoViewerScreen(
          photos: _photos,
          initialIndex: index,
          token: widget.token,
        ),
      ),
    )
        .then((result) {
      if (result == true &&
          mounted) {
        _loadPhotos();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // SELECTION
  // ---------------------------------------------------------------------------

  void _startSelection(
    Photo photo,
  ) {
    setState(() {
      _isSelectionMode = true;
      _selectedPhotoIds.add(
        photo.id,
      );
    });
  }

  void _toggleSelection(
    Photo photo,
  ) {
    setState(() {
      if (_selectedPhotoIds
          .contains(photo.id)) {
        _selectedPhotoIds.remove(
          photo.id,
        );
      } else {
        _selectedPhotoIds.add(
          photo.id,
        );
      }
    });
  }

  void _selectAll() {
    setState(() {
      final allSelected =
          _photos.isNotEmpty &&
          _selectedPhotoIds.length ==
              _photos.length;

      if (allSelected) {
        // IMPORTANT:
        // Keep selection mode active.
        _selectedPhotoIds.clear();
        _isSelectionMode = true;
      } else {
        _selectedPhotoIds
          ..clear()
          ..addAll(
            _photos.map(
              (photo) => photo.id,
            ),
          );

        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
    });
  }

  // ---------------------------------------------------------------------------
  // ADD TO ALBUM
  // ---------------------------------------------------------------------------

  Future<void> _showAlbumPicker() async {
    if (_selectedPhotoIds.isEmpty ||
        _isAddingToAlbum) {
      return;
    }

    setState(() {
      _isAddingToAlbum = true;
    });

    List<Album> albums;

    try {
      albums =
          await _apiService.getAlbums();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAddingToAlbum = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load albums: $e',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      _isAddingToAlbum = false;
    });

    final availableAlbums =
        widget.isRecent
            ? albums
            : albums
                .where(
                  (album) =>
                      album.id !=
                      widget.albumId,
                )
                .toList();

    if (availableAlbums.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'No other albums available.',
          ),
        ),
      );

      return;
    }

    final selectedAlbum =
        await _showAlbumSelectionDialog(
      title: 'Add to album',
      albums: availableAlbums,
    );

    if (selectedAlbum == null ||
        !mounted) {
      return;
    }

    await _addSelectedPhotosToAlbum(
      selectedAlbum,
    );
  }

  Future<void> _addSelectedPhotosToAlbum(
    Album destinationAlbum,
  ) async {
    final ids =
        List<int>.from(
      _selectedPhotoIds,
    );

    setState(() {
      _isAddingToAlbum = true;
    });

    int addedCount = 0;
    int alreadyAddedCount = 0;
    int failedCount = 0;

    for (final photoId in ids) {
      try {
        await _apiService
            .addPhotoToAlbum(
          destinationAlbum.id,
          photoId,
        );

        addedCount++;
      } catch (e) {
        final message =
            e.toString();

        if (message.contains('409')) {
          alreadyAddedCount++;
        } else {
          failedCount++;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _isAddingToAlbum = false;
      _selectedPhotoIds.clear();
      _isSelectionMode = false;
    });

    String message;

    if (failedCount == 0 &&
        alreadyAddedCount == 0) {
      message = addedCount == 1
          ? 'Photo added to '
              '"${destinationAlbum.name}".'
          : '$addedCount photos added to '
              '"${destinationAlbum.name}".';
    } else {
      message =
          '$addedCount added, '
          '$alreadyAddedCount already there, '
          '$failedCount failed.';
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOVE TO ALBUM
  // ---------------------------------------------------------------------------

  Future<void> _showMoveAlbumPicker() async {
    if (widget.isRecent ||
        widget.albumId == null ||
        _selectedPhotoIds.isEmpty ||
        _isAddingToAlbum) {
      return;
    }

    List<Album> albums;

    try {
      albums =
          await _apiService.getAlbums();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load albums: $e',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    final availableAlbums =
        albums
            .where(
              (album) =>
                  album.id !=
                  widget.albumId,
            )
            .toList();

    if (availableAlbums.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'No other albums available.',
          ),
        ),
      );

      return;
    }

    final selectedAlbum =
        await _showAlbumSelectionDialog(
      title: 'Move to album',
      albums: availableAlbums,
    );

    if (selectedAlbum == null ||
        !mounted) {
      return;
    }

    await _moveSelectedPhotosToAlbum(
      selectedAlbum,
    );
  }

  Future<void> _moveSelectedPhotosToAlbum(
    Album destinationAlbum,
  ) async {
    if (widget.albumId == null) {
      return;
    }

    final ids =
        List<int>.from(
      _selectedPhotoIds,
    );

    setState(() {
      _isAddingToAlbum = true;
    });

    int movedCount = 0;
    int failedCount = 0;

    for (final photoId in ids) {
      try {
        await _apiService
            .movePhotoToAlbum(
          widget.albumId!,
          destinationAlbum.id,
          photoId,
        );

        movedCount++;
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;

    setState(() {
      _isAddingToAlbum = false;

      if (failedCount == 0) {
        _photos.removeWhere(
          (photo) =>
              ids.contains(photo.id),
        );
      }

      _selectedPhotoIds.clear();
      _isSelectionMode = false;
    });

    final message =
        failedCount == 0
            ? movedCount == 1
                ? 'Photo moved to '
                    '"${destinationAlbum.name}".'
                : '$movedCount photos moved to '
                    '"${destinationAlbum.name}".'
            : '$movedCount moved, '
                '$failedCount failed.';

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REMOVE FROM ALBUM
  // ---------------------------------------------------------------------------

  Future<void> _removeSelectedPhotos() async {
    if (widget.isRecent ||
        widget.albumId == null ||
        _selectedPhotoIds.isEmpty ||
        _isRemoving) {
      return;
    }

    final count =
        _selectedPhotoIds.length;

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Remove from album?',
          ),
          content: Text(
            count == 1
                ? 'Remove this photo from '
                  '"${widget.albumName}"?'
                : 'Remove $count photos from '
                  '"${widget.albumName}"?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isRemoving = true;
    });

    final ids =
        List<int>.from(
      _selectedPhotoIds,
    );

    int removedCount = 0;
    int failedCount = 0;

    for (final photoId in ids) {
      try {
        await _apiService
            .removePhotoFromAlbum(
          widget.albumId!,
          photoId,
        );

        removedCount++;
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;

    setState(() {
      _photos.removeWhere(
        (photo) =>
            ids.contains(photo.id),
      );

      _selectedPhotoIds.clear();
      _isSelectionMode = false;
      _isRemoving = false;
    });

    final message =
        failedCount == 0
            ? removedCount == 1
                ? 'Photo removed from album.'
                : '$removedCount photos removed from album.'
            : '$removedCount removed, '
                '$failedCount failed.';

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOVE TO TRASH
  // ---------------------------------------------------------------------------

  Future<void> _moveSelectedPhotosToTrash()
      async {
    if (_selectedPhotoIds.isEmpty ||
        _isRemoving) {
      return;
    }

    final count =
        _selectedPhotoIds.length;

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Move to Trash?',
          ),
          content: Text(
            count == 1
                ? 'This photo will be moved to Trash. '
                  'You can restore it for 30 days.'
                : '$count photos will be moved to Trash. '
                  'You can restore them for 30 days.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Move to Trash',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isRemoving = true;
    });

    final ids =
        List<int>.from(
      _selectedPhotoIds,
    );

    int movedCount = 0;
    int failedCount = 0;

    for (final photoId in ids) {
      try {
        await _apiService
            .movePhotoToTrash(
          photoId,
        );

        movedCount++;
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;

    setState(() {
      _photos.removeWhere(
        (photo) =>
            ids.contains(photo.id),
      );

      _selectedPhotoIds.clear();
      _isSelectionMode = false;
      _isRemoving = false;
    });

    final message =
        failedCount == 0
            ? movedCount == 1
                ? 'Photo moved to Trash.'
                : '$movedCount photos moved to Trash.'
            : '$movedCount moved to Trash, '
                '$failedCount failed.';

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ALBUM DIALOG
  // ---------------------------------------------------------------------------

  Future<Album?>
      _showAlbumSelectionDialog({
    required String title,
    required List<Album> albums,
  }) {
    return showDialog<Album>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: albums.length,
              separatorBuilder:
                  (_, _) {
                return const Divider(
                  height: 1,
                );
              },
              itemBuilder:
                  (context, index) {
                final album =
                    albums[index];

                return ListTile(
                  leading:
                      const Icon(
                    Icons
                        .photo_album_outlined,
                  ),
                  title: Text(
                    album.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    album.photoCount == 1
                        ? '1 photo'
                        : '${album.photoCount} photos',
                  ),
                  trailing:
                      const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: () {
                    Navigator.pop(
                      dialogContext,
                      album,
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (!_isSelectionMode) {
      return AppBar(
        title:
            Text(widget.albumName),
        actions: [
          if (_photos.isNotEmpty)
            IconButton(
              tooltip:
                  'Select photos',
              onPressed: () {
                setState(() {
                  _isSelectionMode =
                      true;
                });
              },
              icon: const Icon(
                Icons.checklist,
              ),
            ),
        ],
      );
    }

    final selectedCount =
        _selectedPhotoIds.length;

    final allSelected =
        _photos.isNotEmpty &&
        selectedCount ==
            _photos.length;

    return AppBar(
      leading: IconButton(
        tooltip:
            'Cancel selection',
        onPressed:
            _clearSelection,
        icon: const Icon(
          Icons.close,
        ),
      ),
      title: Text(
        '$selectedCount selected',
      ),
      actions: [
        TextButton(
          onPressed:
              _photos.isEmpty
                  ? null
                  : _selectAll,
          child: Text(
            allSelected
                ? 'Deselect all'
                : 'Select all',
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip:
              'Add to album',
          onPressed:
              selectedCount == 0 ||
                      _isAddingToAlbum
                  ? null
                  : _showAlbumPicker,
          icon:
              _isAddingToAlbum
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons
                          .library_add_outlined,
                    ),
        ),
        if (!widget.isRecent) ...[
          IconButton(
            tooltip:
                'Move to album',
            onPressed:
                selectedCount == 0 ||
                        _isAddingToAlbum
                    ? null
                    : _showMoveAlbumPicker,
            icon: const Icon(
              Icons
                  .drive_file_move_outlined,
            ),
          ),
          IconButton(
            tooltip:
                'Remove from album',
            onPressed:
                selectedCount == 0 ||
                        _isRemoving
                    ? null
                    : _removeSelectedPhotos,
            icon: const Icon(
              Icons
                  .remove_circle_outline,
            ),
          ),
        ],
        IconButton(
          tooltip:
              'Move to Trash',
          onPressed:
              selectedCount == 0 ||
                      _isRemoving
                  ? null
                  : _moveSelectedPhotosToTrash,
          icon: const Icon(
            Icons.delete_outline,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
            ),
            const SizedBox(
              height: 16,
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                });

                _loadPhotos();
              },
              child:
                  const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPhotos,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(
              height: 180,
            ),
            Icon(
              widget.isRecent
                  ? Icons.access_time
                  : Icons
                      .photo_album_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
            ),
            const SizedBox(
              height: 16,
            ),
            Center(
              child: Text(
                widget.isRecent
                    ? 'No recent photos'
                    : 'This album is empty',
                style:
                    const TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: GridView.builder(
        padding:
            const EdgeInsets.all(4),
        itemCount:
            _photos.length,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemBuilder:
            (context, index) {
          final photo =
              _photos[index];

          final selected =
              _selectedPhotoIds
                  .contains(
            photo.id,
          );

          return GestureDetector(
            onTap: () {
              _openPhoto(
                photo,
                index,
              );
            },
            onLongPress: () {
              if (!_isSelectionMode) {
                _startSelection(
                  photo,
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    6,
                  ),
                  child:
                      PhotoThumbnail(
                    photo: photo,
                    token:
                        widget.token,
                  ),
                ),
                if (selected)
                  Container(
                    decoration:
                        BoxDecoration(
                      color: Colors.black
                          .withValues(
                        alpha: 0.35,
                      ),
                      border: Border.all(
                        color:
                            Theme.of(
                          context,
                        )
                                .colorScheme
                                .primary,
                        width: 3,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        6,
                      ),
                    ),
                  ),
                if (_isSelectionMode)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration:
                          BoxDecoration(
                        shape:
                            BoxShape.circle,
                        color: selected
                            ? Theme.of(
                                context,
                              )
                                .colorScheme
                                .primary
                            : Colors.black
                                .withValues(
                                alpha: 0.45,
                              ),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              size: 17,
                              color:
                                  Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}