import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class UploadPhotosScreen extends StatefulWidget {
  final String token;
  final int? albumId;

  const UploadPhotosScreen({
    super.key,
    required this.token,
    this.albumId,
  });

  @override
  State<UploadPhotosScreen> createState() => _UploadPhotosScreenState();
}

class _UploadPhotosScreenState extends State<UploadPhotosScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();

  List<XFile> _selectedPhotos = [];
  XFile? _selectedVideo;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
  }

  Future<void> _selectPhotos() async {
    try {
      final photos = await _picker.pickMultiImage(imageQuality: 100);
      if (!mounted) return;
      setState(() {
        _selectedPhotos = photos;
        _selectedVideo = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to select photos.')),
      );
    }
  }

  Future<void> _selectVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (!mounted || video == null) return;
      setState(() {
        _selectedVideo = video;
        _selectedPhotos = [];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to select video.')),
      );
    }
  }

  Future<void> _uploadSelectedMedia() async {
    if ((_selectedPhotos.isEmpty && _selectedVideo == null) || _isUploading) {
      return;
    }

    setState(() => _isUploading = true);

    try {
      int uploadedCount = 0;

      if (_selectedVideo != null) {
        final uploaded = await _apiService.uploadPhoto(_selectedVideo!);
        if (widget.albumId != null) {
          await _apiService.addPhotoToAlbum(widget.albumId!, uploaded.id);
        }
        uploadedCount = 1;
      } else {
        for (final photo in _selectedPhotos) {
          final uploaded = await _apiService.uploadPhoto(photo);
          if (widget.albumId != null) {
            await _apiService.addPhotoToAlbum(widget.albumId!, uploaded.id);
          }
          uploadedCount++;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.albumId != null
                ? '$uploadedCount media item(s) added to album.'
                : '$uploadedCount media item(s) uploaded successfully.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.albumId != null ? 'Add Media' : 'Upload Media';
    final hasSelection = _selectedPhotos.isNotEmpty || _selectedVideo != null;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: hasSelection ? _buildPreview() : _buildEmptyState(),
            ),
            const SizedBox(height: 16),
            if (!hasSelection)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selectPhotos,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Photos'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selectVideo,
                      icon: const Icon(Icons.videocam),
                      label: const Text('Video'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isUploading ? null : _selectPhotos,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isUploading ? null : _uploadSelectedMedia,
                      child: _isUploading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _selectedVideo != null
                                  ? 'Upload Video'
                                  : 'Upload ${_selectedPhotos.length}',
                            ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.perm_media_outlined, size: 64),
          const SizedBox(height: 16),
          Text(
            widget.albumId != null
                ? 'Select photos or a video to add'
                : 'Select photos or a video to upload',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_selectedVideo != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_file, size: 96),
            const SizedBox(height: 16),
            Text(
              _selectedVideo!.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      itemCount: _selectedPhotos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final photo = _selectedPhotos[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(photo.path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Icon(Icons.image)),
          ),
        );
      },
    );
  }
}
