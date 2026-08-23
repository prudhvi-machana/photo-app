import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../models/trash_photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';

class TrashScreen extends StatefulWidget {
  final String token;

  const TrashScreen({
    super.key,
    required this.token,
  });

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final ApiService _apiService = ApiService();

  List<TrashPhoto> _photos = [];

  bool _isLoading = true;
  bool _isSelectionMode = false;

  final Set<int> _selectedIds = {};

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _apiService.setToken(widget.token);
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    try {
      final photos = await _apiService.getTrashPhotos();

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
        _errorMessage = 'Failed to load Trash.';
      });
    }
  }

  void _toggleSelection(int photoId) {
    setState(() {
      if (_selectedIds.contains(photoId)) {
        _selectedIds.remove(photoId);
      } else {
        _selectedIds.add(photoId);
      }

      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _enterSelection(int photoId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(photoId);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _photos.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(
            _photos.map((photo) => photo.id),
          );

        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty) return;

    final selected = List<int>.from(_selectedIds);

    try {
      for (final photoId in selected) {
        await _apiService.restorePhoto(photoId);
      }

      if (!mounted) return;

      setState(() {
        _photos.removeWhere(
          (photo) => selected.contains(photo.id),
        );

        _selectedIds.clear();
        _isSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selected.length == 1
                ? 'Photo restored'
                : '${selected.length} photos restored',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to restore photos'),
        ),
      );
    }
  }

  Future<void> _permanentlyDeleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete permanently?'),
          content: Text(
            count == 1
                ? 'This photo will be permanently deleted. '
                    'This cannot be undone.'
                : '$count photos will be permanently deleted. '
                    'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final selected = List<int>.from(_selectedIds);

    try {
      for (final photoId in selected) {
        await _apiService.permanentlyDeletePhoto(photoId);
      }

      if (!mounted) return;

      setState(() {
        _photos.removeWhere(
          (photo) => selected.contains(photo.id),
        );

        _selectedIds.clear();
        _isSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Photo permanently deleted'
                : '$count photos permanently deleted',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete photos'),
        ),
      );
    }
  }

  Future<void> _showPhotoActions(TrashPhoto photo) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore'),
                onTap: () {
                  Navigator.pop(context, 'restore');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: const Text('Delete permanently'),
                onTap: () {
                  Navigator.pop(context, 'delete');
                },
              ),
            ],
          ),
        );
      },
    );

    if (action == 'restore') {
      await _restoreSingle(photo);
    } else if (action == 'delete') {
      await _deleteSingle(photo);
    }
  }

  Future<void> _restoreSingle(TrashPhoto photo) async {
    try {
      await _apiService.restorePhoto(photo.id);

      if (!mounted) return;

      setState(() {
        _photos.removeWhere(
          (item) => item.id == photo.id,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo restored'),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to restore photo'),
        ),
      );
    }
  }

  Future<void> _deleteSingle(TrashPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete permanently?'),
          content: const Text(
            'This photo will be permanently deleted. '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.permanentlyDeletePhoto(photo.id);

      if (!mounted) return;

      setState(() {
        _photos.removeWhere(
          (item) => item.id == photo.id,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo permanently deleted'),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete photo'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Trash'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                ),
                IconButton(
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore),
                  onPressed: _restoreSelected,
                ),
                IconButton(
                  tooltip: 'Delete permanently',
                  icon: const Icon(Icons.delete_forever),
                  onPressed: _permanentlyDeleteSelected,
                ),
              ]
            : [
                if (_photos.isNotEmpty)
                  IconButton(
                    tooltip: 'Select',
                    icon: const Icon(
                      Icons.check_circle_outline,
                    ),
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = true;
                      });
                    },
                  ),
              ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                });

                _loadTrash();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadTrash,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(
              Icons.delete_outline,
              size: 72,
            ),
            SizedBox(height: 16),
            Center(
              child: Text(
                'Trash is empty',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Deleted photos will stay here for 30 days.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTrash,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: _photos.length,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemBuilder: (context, index) {
          final photo = _photos[index];
          final selected = _selectedIds.contains(photo.id);

          return GestureDetector(
            onTap: () {
              if (_isSelectionMode) {
                _toggleSelection(photo.id);
              } else {
                _showPhotoActions(photo);
              }
            },
            onLongPress: () {
              if (!_isSelectionMode) {
                _enterSelection(photo.id);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: PhotoThumbnail(
                    photo: _photoFromTrash(photo),
                    token: widget.token,
                  ),
                ),

                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: 0.65,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${photo.daysRemaining} days left',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),

                if (selected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          width: 3,
                        ),
                      ),
                      child: const Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Photo _photoFromTrash(TrashPhoto photo) {
    return Photo(
      id: photo.id,
      filename: photo.filename,
      originalFilename: photo.originalFilename,
      mimeType: photo.mimeType,
      size: photo.size,
      uploadedAt: photo.uploadedAt.toIso8601String(),
      thumbnailUrl: photo.thumbnailUrl,
    );
  }
}