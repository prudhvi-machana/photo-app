import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'photo_viewer_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final String token;

  const FavoritesScreen({super.key, required this.token});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
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
      final photos = await _apiService.getFavoritePhotos();
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
        _errorMessage = 'Failed to load favourites.';
      });
    }
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
    ).then((result) {
      if (result == true && mounted) _loadPhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadPhotos, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPhotos,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: Icon(Icons.favorite_border, size: 56)),
            SizedBox(height: 16),
            Center(child: Text('No favourite photos yet.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: GridView.builder(
        padding: const EdgeInsets.all(2),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _photos.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemBuilder: (context, index) {
          final photo = _photos[index];
          return GestureDetector(
            onTap: () => _openPhoto(index),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PhotoThumbnail(photo: photo, token: widget.token),
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: Icon(Icons.favorite, color: Colors.white, size: 20),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
