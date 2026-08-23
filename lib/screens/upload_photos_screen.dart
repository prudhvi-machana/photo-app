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
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
  }

  Future<void> _selectPhotos() async {
    try {
      final photos = await _picker.pickMultiImage(
        imageQuality: 100,
      );

      if (!mounted) return;

      setState(() {
        _selectedPhotos = photos;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to select photos.'),
        ),
      );
    }
  }

  Future<void> _uploadPhotos() async {
    if (_selectedPhotos.isEmpty || _isUploading) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      int uploadedCount = 0;

      for (final photo in _selectedPhotos) {
        final uploadedPhoto = await _apiService.uploadPhoto(photo);

        if (widget.albumId != null) {
          await _apiService.addPhotoToAlbum(
            widget.albumId!,
            uploadedPhoto.id,
          );
        }

        uploadedCount++;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.albumId != null
                ? '$uploadedCount photo(s) added to album.'
                : '$uploadedCount photo(s) uploaded successfully.',
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo upload failed: $e',
          ),
        ),
      );

      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.albumId != null
        ? 'Add Photos'
        : 'Upload Photos';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _selectedPhotos.isEmpty
                  ? _buildEmptyState()
                  : _buildPhotoGrid(),
            ),
            const SizedBox(height: 16),
            if (_selectedPhotos.isEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectPhotos,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Select Photos'),
                ),
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
                      onPressed: _isUploading ? null : _uploadPhotos,
                      child: _isUploading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Upload ${_selectedPhotos.length}',
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
          const Icon(
            Icons.photo_library_outlined,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            widget.albumId != null
                ? 'Select photos to add'
                : 'Select photos to upload',
            style: const TextStyle(
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
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
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade300,
                child: const Icon(Icons.image),
              );
            },
          ),
        );
      },
    );
  }
}