import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'photo_viewer_screen.dart';

class PhotosScreen extends StatefulWidget {
  final String token;

  const PhotosScreen({
    super.key,
    required this.token,
  });

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final ApiService _apiService = ApiService();

  List<Photo> _photos = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await _apiService.getPhotos();
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
        _errorMessage = 'Failed to load photos.';
      });
    }
  }

  Future<void> _refresh() async {
    await _loadPhotos();
  }

  Map<DateTime, List<Photo>> _groupPhotosByDate() {
    final groups = <DateTime, List<Photo>>{};

    for (final photo in _photos) {
      final date = DateTime.parse(photo.uploadedAt).toLocal();
      final key = DateTime(date.year, date.month, date.day);
      groups.putIfAbsent(key, () => []).add(photo);
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
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (date.year == today.year) {
      return '${months[date.month - 1]} ${date.day}';
    }

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _openPhoto(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          photos: _photos,
          initialIndex: index,
          token: widget.token,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadPhotos,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: Text('No photos yet.')),
          ],
        ),
      );
    }

    final groups = _groupPhotosByDate();
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
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
                    final photo = groups[date]![index];
                    final globalIndex = _photos.indexOf(photo);

                    return GestureDetector(
                      onTap: () => _openPhoto(globalIndex),
                      child: PhotoThumbnail(
                        photo: photo,
                        token: widget.token,
                      ),
                    );
                  },
                  childCount: groups[date]!.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
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
    );
  }
}
